"""Exercise EC2 resource selection and the prepare, execute, refresh menu flow."""

import base64
from collections import deque
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from test_setup import fixture
from core import AWS
from flows import AWSWizard
from setup import UI


ACCOUNT = '123456789012'
REGION = 'us-east-1'
RUN = 'ec2-resource-test'
VPC = {'VpcId': 'vpc-test', 'CidrBlock': '10.0.0.0/16', 'State': 'available'}
POLICY = 'arn:aws:iam::123456789012:policy/existing-console-policy'


class ResourceInventory:
    def __init__(self, new):
        self.region = REGION
        self.subnets = [self.subnet(letter) for letter in ('ab' if new else 'abc')]
        self.groups = [] if new else [self.group('broker', [22, 9090, 9102, 9103]), self.group('efs', [2049])]
        self.zone = None if new else 'ZEXISTING'
        self.bucket = None if new else 'existing-data'
        self.roles = [] if new else ['existing-broker', 'existing-console']
        self.endpoint_routes = ['rtb-main'] if new else ['rtb-main', 'rtb-c']
        self.applied = []

    @staticmethod
    def subnet(letter):
        number = 'abc'.index(letter) + 1
        return {'SubnetId': f'subnet-{letter}', 'VpcId': VPC['VpcId'], 'State': 'available',
                'AvailabilityZone': REGION + letter, 'AvailabilityZoneId': f'use1-az{number}',
                'CidrBlock': f'10.0.{number}.0/24', 'AvailableIpAddressCount': 200}

    @staticmethod
    def group(name, ports):
        return {'GroupName': name, 'GroupId': f'sg-{name}', 'VpcId': VPC['VpcId'],
                'IpPermissions': [{'IpProtocol': 'tcp', 'FromPort': port, 'ToPort': port,
                                   'IpRanges': [{'CidrIp': VPC['CidrBlock']}]} for port in ports],
                'IpPermissionsEgress': []}

    @staticmethod
    def role(name):
        return {'RoleName': name, 'Arn': f'arn:aws:iam::{ACCOUNT}:role/{name}',
                'AssumeRolePolicyDocument': {'Statement': [{
                    'Effect': 'Allow', 'Principal': {'Service': 'ec2.amazonaws.com'}, 'Action': 'sts:AssumeRole'
                }]}}

    def read(self, service, operation, *args):
        if operation not in AWS.ALLOWED[service]:
            raise AssertionError(f'Wizard attempted {service} {operation}')
        response = {
            'get-caller-identity': {'Account': ACCOUNT},
            'describe-vpcs': {'Vpcs': [VPC]},
            'describe-subnets': {'Subnets': self.subnets},
            'describe-vpc-attribute': {'EnableDnsSupport': {'Value': True}, 'EnableDnsHostnames': {'Value': True}},
            'describe-availability-zones': {'AvailabilityZones': [{'ZoneName': REGION + az} for az in 'abc']},
            'describe-instance-type-offerings': {'InstanceTypeOfferings': [{'InstanceType': 'r6i.large'}]},
            'describe-images': {'Images': [
                {'ImageId': 'ami-test', 'RootDeviceName': '/dev/xvda', 'Architecture': 'x86_64', 'State': 'available'}
            ]},
            'get-parameter': {'Parameter': {'Value': 'ami-test'}},
            'describe-key-pairs': {'KeyPairs': [{'KeyName': 'existing-key', 'KeyPairId': 'key-test'}]},
            'list-hosted-zones-by-vpc': {'HostedZoneSummaries': [
                {'Name': 'orders.internal.', 'HostedZoneId': self.zone}
            ] if self.zone else []},
            'get-hosted-zone': {'HostedZone': {'Id': self.zone, 'Name': 'orders.internal.', 'Config': {'PrivateZone': True}},
                                'VPCs': [{'VPCId': VPC['VpcId'], 'VPCRegion': REGION}]},
            'list-tags-for-resource': {'ResourceTagSet': {'Tags': []}},
            'list-buckets': {'Buckets': [{'Name': name} for name in ('automq-ops-test', self.bucket) if name]},
            'get-bucket-location': {'LocationConstraint': None},
            'get-bucket-tagging': {'TagSet': []},
            'get-bucket-lifecycle-configuration': {'Rules': []},
            'describe-security-groups': {'SecurityGroups': self.groups},
            'list-roles': {'Roles': [self.role(name) for name in self.roles]},
            'list-attached-role-policies': {'AttachedPolicies': [{'PolicyArn': POLICY}] if args[-1:] == ('existing-console',) else []},
            'describe-route-tables': {'RouteTables': [
                {'RouteTableId': 'rtb-main', 'Associations': [{'Main': True}]},
                {'RouteTableId': 'rtb-c', 'Associations': [
                    {'SubnetId': row['SubnetId']} for row in self.subnets if row['SubnetId'] == 'subnet-c'
                ]},
            ]},
            'describe-vpc-endpoints': {'VpcEndpoints': [
                {'VpcEndpointId': 'vpce-existing', 'VpcId': VPC['VpcId'], 'VpcEndpointType': 'Gateway',
                 'ServiceName': f'com.amazonaws.{REGION}.s3', 'State': 'available',
                 'RouteTableIds': self.endpoint_routes, 'PolicyDocument': '{"Version":"2012-10-17","Statement":[]}'},
            ]},
        }
        if operation == 'get-role':
            assert args[-1] in self.roles
            return {'Role': self.role(args[-1])}
        if operation == 'list-instance-profiles-for-role':
            assert args[-1] in self.roles
            return {'InstanceProfiles': [{'Arn': f'arn:aws:iam::{ACCOUNT}:instance-profile/{args[-1]}'}]}
        return deepcopy(response[operation])

    def apply(self, path):
        """Model the operator's command execution and subsequent AWS discovery."""
        subprocess.run(['bash', '-n', str(path)], check=True)
        command = path.read_text()
        self.applied.append(path.name)
        if path.name == 'prepare-subnet.sh':
            assert f'--vpc-id {VPC["VpcId"]} --availability-zone {REGION}c --cidr-block 10.0.3.0/24' in command
            self.subnets.append(self.subnet('c'))
        elif path.name == 'prepare-s3-endpoint.sh':
            assert 'modify-vpc-endpoint' in command and '--add-route-table-ids rtb-c' in command
            assert '--policy-document' not in command and '--create-vpc-endpoint' not in command
            self.endpoint_routes.append('rtb-c')
        elif path.name == 'prepare-private-zone.sh':
            assert f'VPCRegion={REGION},VPCId={VPC["VpcId"]}' in command
            self.zone = 'ZPREPARED'
        elif path.name == 'prepare-data-bucket.sh':
            self.bucket = f'automq-setup-{RUN}-{ACCOUNT}-{REGION}'
            assert f'--bucket {self.bucket}' in command and 'put-public-access-block' in command
        elif path.name in ('prepare-cluster-sg.sh', 'prepare-fs-sg.sh', 'prepare-console-sg.sh'):
            name, ports = {
                'prepare-cluster-sg.sh': ('broker', [22, 9090, 9102, 9103]),
                'prepare-fs-sg.sh': ('efs', [2049]),
                'prepare-console-sg.sh': ('console', [22, 8080]),
            }[path.name]
            assert f'--vpc-id {VPC["VpcId"]}' in command
            for port in ports:
                assert f'--port {port} --cidr 10.0.0.0/16' in command
            self.groups.append(self.group(name, ports))
        elif path.name in ('prepare-cluster-role.sh', 'prepare-console-role.sh'):
            name = f'automq-setup-{RUN}-{path.stem.removeprefix("prepare-")}'
            assert f'--role-name {name}' in command and f'--instance-profile-name {name}' in command
            self.roles.append(name)
        else:
            raise AssertionError(path.name)


class ScenarioUI(UI):
    def __init__(self, inventory, answers):
        super().__init__(read=lambda _: 'r', show=self.record)
        self.inventory = inventory
        self.answers = {key: deque(values) for key, values in answers.items()}
        self.step = self.section_title = ''

    @staticmethod
    def record(message):
        if message.startswith('\nERROR:') or message == 'Select a displayed resource by number or exact identifier.':
            raise AssertionError(message)

    def heading(self, title, step=False):
        if step:
            self.step = title.split(' | ', 1)[1]
            self.section_title = ''
        else:
            self.section_title = title
        super().heading(title, step)

    def prompt(self, text, current=None):
        if text.startswith('Enter yes to confirm'):
            return 'yes'
        if text.startswith('Cluster name'):
            return RUN
        if text.startswith('Expected peak BytesIn'):
            return '1'
        key = (self.step, self.section_title)
        if key in self.answers:
            if not self.answers[key]:
                raise AssertionError(f'Unexpected repeated prompt: {key}')
            return self.answers[key].popleft()
        if current is not None:
            return current
        raise AssertionError(f'Unexpected prompt {key} {text}')

    def preparation(self, path, back_label='Back to resource list'):
        choice = super().preparation(path, back_label)
        if choice == 'r':
            self.inventory.apply(path)
        return choice


class EC2ResourceStories(unittest.TestCase):
    def run_scenario(self, new=False, managed=False):
        inventory = ResourceInventory(new)
        choose = {
            ('Choose Console', 'Console environment'): ['new' if new else 'existing'],
            ('Choose VPC', 'Select VPC'): [VPC['VpcId']],
            ('Availability zones', 'Availability-zone layout'): ['3'],
            ('Compute subnets', 'Compute subnets'): ['c', '1,2,3'] if new else ['1,2,3'],
            ('Compute subnets', 'New subnet AZ'): ['us-east-1c', '10.0.3.0/24'],
            ('WAL storage', 'WAL storage'): ['FSWAL'],
            ('Instance type', 'Instance type available in every selected AZ'): ['r6i.large'],
            ('DNS mode', 'DNS mode'): ['public' if managed else 'private'],
            ('DNS resources', 'Select private hosted zone'): ['c', 'ZPREPARED'] if new else ['ZEXISTING'],
            ('Data Bucket', 'Data Bucket'): ['existing', 'c', f'automq-setup-{RUN}-{ACCOUNT}-{REGION}'] if new
                                           else ['managed'] if managed else ['existing', 'existing-data'],
            ('Cluster security group', 'Security group preparation'): ['managed' if managed else 'existing'],
            ('Cluster security group', 'Security groups'): ['c', '1'] if new else ['1'],
            ('File system subnets', 'EFS mount-target subnets'): ['1,2,3'],
            ('File system security group', 'Security group preparation'): ['managed' if managed else 'existing'],
            ('File system security group', 'Security groups'): ['c', '2'] if new else ['2'],
            ('Console subnet', 'Console subnet'): ['1'],
            ('Console security group', 'Select Console security group'): ['c', 'sg-console'],
            ('Console SSH key pair', 'Select SSH key pair (private key stays with you)'): ['existing-key'],
            ('AutoMQ Cluster Role', 'Select Role'): ['c', f'automq-setup-{RUN}-cluster-role'] if new else ['existing-broker'],
            ('Console Role', 'Select Role'): ['c', f'automq-setup-{RUN}-console-role'] if new else ['existing-console'],
        }
        home = dict(fixture()['home'], clientId='test-id', clientSecret='test-secret')
        config = base64.b64encode(json.dumps(home).encode()).decode()
        command = f'docker run -e CONFIG={config} -e CLOUD_PROVIDER=aws automq.azurecr.io/automq/automq-byoc-console:8.4.13-aws'
        public_dns = {'hostedZoneId': 'ZPUBLIC', 'crossAccountRole': 'arn:aws:iam::999999999999:role/dns'}
        with tempfile.TemporaryDirectory() as tmp, patch('setup.read_home_command', return_value=command), \
                patch('home.prepare_public_dns', return_value=public_dns) as home_dns, \
                patch('getpass.getpass', return_value='test-password-long'):
            output = Path(tmp) / 'bundle'
            ui = ScenarioUI(inventory, choose)
            wizard = AWSWizard(output, ui, aws_factory=lambda _: inventory, home_reader=lambda _: {'available': True})
            wizard.run()
            body = json.loads((output / 'cluster-request.json').read_text())
            review = json.loads((output / 'review.json').read_text())
            console_policy = json.loads((output / 'console-role-policy.json').read_text())
            spec = body['spec']
            sids = {statement['Sid'] for statement in console_policy['Statement']}
            actions = {action for statement in console_policy['Statement'] for action in statement['Action']}
            self.assertEqual('CreateDataBucket' in sids, managed)
            self.assertEqual('ec2:CreateSecurityGroup' in actions, managed)
            self.assertEqual(spec['instanceRole'], inventory.roles[0])
            self.assertEqual([x['subnet'] for x in spec['networks']], ['subnet-a', 'subnet-b', 'subnet-c'])
            self.assertEqual(spec['fileSystemForFsWal']['subnetIds'], ['subnet-a', 'subnet-b', 'subnet-c'])
            self.assertEqual((output / 'install-console.sh').exists(), new)
            self.assertTrue((output / 'generate-curl.sh').is_file())
            self.assertFalse((output / 'prepare-s3-endpoint.sh').exists())
            for role, purpose in zip(inventory.roles, ('cluster-role', 'console-role')):
                authorization = (output / f'authorize-{purpose}.sh').read_text()
                self.assertIn('aws iam attach-role-policy', authorization)
                self.assertIn(f'--role-name {role} --policy-arn', authorization)
            if managed:
                self.assertEqual(spec['dnsZoneType'], 'PUBLIC')
                self.assertEqual(spec['dataBuckets'], [])
                self.assertNotIn('securityGroups', spec)
                self.assertEqual(body['features']['inboundRules'], [
                    {'listenerName': 'BROKER_SASL', 'cidrs': ['10.0.0.0/16']}
                ])
                self.assertNotIn('securityGroups', spec['fileSystemForFsWal'])
                home_dns.assert_called_once()
            else:
                self.assertEqual(spec['dnsZone'], inventory.zone)
                self.assertEqual(spec['dataBuckets'], [{'bucketName': inventory.bucket}])
                self.assertEqual(spec['securityGroups'], ['sg-broker'])
                self.assertEqual(spec['fileSystemForFsWal']['securityGroups'], ['sg-efs'])
                self.assertNotIn('inboundRules', body['features'])
                home_dns.assert_not_called()
            self.assertEqual(review['vpcServiceAccess']['s3MissingRouteTables'], [])
            self.assertEqual(review['vpcServiceAccess']['s3Gateways'][0]['VpcEndpointId'], 'vpce-existing')
            if new:
                launch = (output / 'prepare-console-ec2.sh').read_text()
                self.assertIn(f'instance-profile/{inventory.roles[1]}', launch)
                self.assertIn('--key-name existing-key', launch)
                self.assertCountEqual(inventory.applied, [
                    'prepare-subnet.sh', 'prepare-private-zone.sh', 'prepare-data-bucket.sh', 'prepare-cluster-sg.sh',
                    'prepare-fs-sg.sh', 'prepare-console-sg.sh', 'prepare-s3-endpoint.sh',
                    'prepare-cluster-role.sh', 'prepare-console-role.sh',
                ])
            else:
                self.assertIn(POLICY, json.dumps(console_policy))
                self.assertEqual(inventory.applied, [])
                self.assertFalse(list(output.glob('prepare-*.sh')))

    def test_select_existing_resources(self):
        self.run_scenario()

    def test_prepare_missing_resources_and_refresh(self):
        self.run_scenario(new=True)

    def test_reuse_console_and_network_with_cmp_managed_dependencies(self):
        self.run_scenario(managed=True)
