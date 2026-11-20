import base64
import contextlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from threading import Thread
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import AWS, Back, SetupError, combine, parse_home, policies, request_body, role_commands, split_policy, write_private, zone_commands, export
from setup import UI, Wizard


def fixture():
    return {'home': {'region': 'us-east-1', 'environmentId': 'env-test', 'opsBucket': {'bucketName': 'automq-ops-test'}},
            'account': '123456789012', 'name': 'test-123', 'peak': 1,
            'vpc': {'VpcId': 'vpc-123'}, 'subnet': {'SubnetId': 'subnet-123', 'AvailabilityZone': 'us-east-1a', 'AvailabilityZoneId': 'use1-az1'},
            'zone': {'Id': '/hostedzone/ZTEST'}, 'instance_type': 'r6i.large', 'network': {},
            'cluster_role': {'RoleName': 'cluster', 'Arn': 'arn:aws:iam::123456789012:role/cluster'},
            'console_role': {'RoleName': 'console', 'Arn': 'arn:aws:iam::123456789012:role/console'}}

class Tests(unittest.TestCase):
    def test_home_parse_does_not_execute(self):
        data = {'environmentId': 'env-test', 'clientId': 'id', 'clientSecret': 'SECRET', 'region': 'us-east-1', 'opsBucket': {'bucketName': 'bucket-test'}}
        config = base64.b64encode(json.dumps(data).encode()).decode()
        command = f'sudo docker run -v ${{Replace with your actual host dir}}:/root -e CONFIG={config} -e CLOUD_PROVIDER=aws -e CONSOLE_INITIAL_PASSWORD=${{Your initial password}} automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws'
        self.assertEqual(parse_home(command)['clientSecret'], 'SECRET')
        with self.assertRaises(SetupError):
            parse_home(command + '; touch /tmp/should-not-exist')
        with self.assertRaises(SetupError):
            parse_home(command.replace(config, 'invalid'))

    def test_cloud_write_fails_before_subprocess(self):
        def runner(*args, **kwargs):
            self.fail('Write reached runner')
        with self.assertRaises(SetupError):
            AWS('us-east-1', runner).read('ec2', 'run-instances')

    def test_read_error_is_not_empty_and_redacts(self):
        def runner(*args, **kwargs):
            return subprocess.CompletedProcess([], 1, '', 'An error occurred (AccessDenied) when calling ListRoles: SECRET')
        with self.assertRaisesRegex(SetupError, 'AccessDenied') as raised:
            AWS('us-east-1', runner).read('iam', 'list-roles')
        self.assertNotIn('SECRET', str(raised.exception))

    def test_pagination_stable_and_confirm_explicit(self):
        inputs = iter(['n', '22', '', 'yes'])
        ui = UI(lambda _: next(inputs), lambda _: None)
        rows = [{'id': str(n)} for n in range(45)]
        self.assertEqual(ui.choose('resources', lambda: rows, lambda x: x['id'], lambda x: 'id-' + x['id'])['id'], '21')
        ui.confirm('confirm')

    def test_back_keeps_target_clears_downstream(self):
        with tempfile.TemporaryDirectory() as temp:
            wizard = Wizard(Path(temp) / 'out', UI(show=lambda _: None))
            wizard.nodes = ['one', 'two', 'three']
            calls = []
            def one():
                wizard.state['one'] = 1
            def two():
                calls.append(2)
                if len(calls) == 2:
                    self.assertEqual(wizard.state, {'one': 1, 'two': 2})
                wizard.state['two'] = 2
            def three():
                if len(calls) == 1:
                    wizard.state['downstream'] = 'stale'
                    raise Back()
            wizard.one, wizard.two, wizard.three = one, two, three
            self.assertNotIn('downstream', wizard.run())

    def test_back_from_instance_returns_to_subnet(self):
        with tempfile.TemporaryDirectory() as temp:
            output = []
            wizard = Wizard(Path(temp) / 'out', UI(show=output.append))
            wizard.nodes = ['network', 'instance_type']
            visits = []
            def network():
                if visits:
                    self.assertEqual(wizard.state['subnet'], {'SubnetId': 'subnet-one'})
                    self.assertNotIn('instance_type', wizard.state)
                visits.append('subnet')
                wizard.state['subnet'] = {'SubnetId': 'subnet-one'}
            def instance():
                if len(visits) == 1:
                    wizard.state['instance_type'] = 'discard-me'
                    wizard.state['subnet']['SubnetId'] = 'mutated'
                    raise Back()
                wizard.state['instance_type'] = 'r6i.large'
            wizard.network, wizard.instance_type = network, instance
            wizard.run()
            self.assertEqual([x for x in output if x.startswith('Step ')], [
                'Step 1 | Choose compute subnet', 'Step 2 | Choose instance type',
                'Step 1 | Choose compute subnet', 'Step 2 | Choose instance type'])

    def test_existing_console_back_skips_new_console_nodes(self):
        with tempfile.TemporaryDirectory() as temp:
            output = []
            wizard = Wizard(Path(temp) / 'out', UI(show=output.append))
            wizard.state = {'console_mode': 'existing'}
            wizard.nodes = ['cluster_sg', 'console_source', 'console_sg', 'console_key',
                            'console_password', 'existing_console_subnet']
            visits = []
            wizard.cluster_sg = lambda: visits.append('cluster_sg')
            def subnet():
                if len(visits) == 1:
                    raise Back()
                visits.append('console_subnet')
            wizard.existing_console_subnet = subnet
            wizard.run()
            self.assertEqual(visits, ['cluster_sg', 'cluster_sg', 'console_subnet'])
            self.assertEqual([x for x in output if x.startswith('Step ')], [
                'Step 1 | Cluster security group', 'Step 2 | Existing Console subnet',
                'Step 1 | Cluster security group', 'Step 2 | Existing Console subnet'])

    def test_role_profiles_missing_and_multiple(self):
        from core import validate_role
        role = {'RoleName': 'example', 'AssumeRolePolicyDocument': {'Statement': [
            {'Effect': 'Allow', 'Principal': {'Service': 'ec2.amazonaws.com'}, 'Action': 'sts:AssumeRole'}]}}
        class Client:
            region = 'us-east-1'
            profiles = []
            def read(self, *args): return {'InstanceProfiles': self.profiles}
        client = Client()
        with self.assertRaises(SetupError) as error:
            validate_role(client, role)
        self.assertIn('has no Instance Profile', str(error.exception))
        self.assertIn('create-instance-profile', str(error.exception))
        self.assertIn('--role-name example', str(error.exception))
        client.profiles = [{'Arn': 'profile-1'}, {'Arn': 'profile-2'}]
        messages = []
        self.assertEqual(validate_role(client, role, messages.append), client.profiles[0])
        self.assertIn('CMP uses the first', messages[0])

    def test_policy_limits_and_exact_scopes(self):
        cluster, console = policies(fixture())
        by_sid = {s['Sid']: s for s in console['Statement']}
        self.assertEqual(by_sid['PassClusterRole']['Resource'], [fixture()['cluster_role']['Arn']])
        self.assertNotIn('<', json.dumps(console))
        self.assertEqual(by_sid['RunNewCompute']['Condition']['StringEquals']['aws:RequestTag/automqVendor'], 'automq')
        self.assertTrue(all(len(json.dumps(p, separators=(',', ':'))) <= 6144 for p in split_policy(console)))
        self.assertFalse(any('glue:' in a.lower() for s in console['Statement'] for a in s['Action']))
        self.assertEqual(cluster['Statement'][0]['Condition']['StringEquals']['s3:ResourceAccount'], '123456789012')

    def test_launch_template_network_interface_tags(self):
        _, console = policies(fixture())
        statement = next(s for s in console['Statement'] if s['Sid'] == 'TagNetworkInterfaceDuringRun')
        self.assertEqual(statement['Resource'], ['arn:aws:ec2:us-east-1:123456789012:network-interface/*'])
        self.assertEqual(statement['Action'], ['ec2:CreateTags'])
        self.assertEqual(statement['Condition']['StringEquals'], {
            'ec2:CreateAction': 'RunInstances', 'aws:RequestTag/automqVendor': 'automq'})

    def test_unresolved_parameter_blocks_output(self):
        with self.assertRaises(SetupError):
            combine({'x': {'Statement': [{'Sid': 'x', 'Resource': ['<missing>']}]}}, ['x'], {})

    def test_api_mapping(self):
        body = request_body(fixture())
        self.assertEqual(body['spec']['instanceRole'], 'cluster')
        self.assertEqual(body['spec']['reservedNodeCount'], 3)
        self.assertEqual(body['features']['walMode'], 'EBSWAL')
        self.assertNotIn('securityGroups', body['spec'])
        self.assertEqual(body['spec']['dataBuckets'], [])
        self.assertNotIn('tableTopic', body['features'])

    def test_artifacts_and_shell_syntax(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            state = fixture()
            role_commands(path, 'us-east-1', 'test-123', 'cluster-role')
            zone_commands(path, state)
            export(path, state)
            for f in path.iterdir():
                self.assertEqual(f.stat().st_mode & 0o777, 0o600)
                if f.suffix == '.sh':
                    subprocess.run(['bash', '-n', str(f)], check=True)
                if f.suffix == '.json':
                    json.loads(f.read_text())
            self.assertNotIn('clientSecret', (path / 'review.json').read_text())

    def test_no_symlink_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            (path / 'target').write_text('keep')
            (path / 'link').symlink_to(path / 'target')
            with self.assertRaises(OSError):
                write_private(path / 'link', 'replace')
            self.assertEqual((path / 'target').read_text(), 'keep')


class FullStoryTests(unittest.TestCase):
    def test_complete_interactive_story(self):
        from unittest.mock import patch
        from core import validate_network
        vpc = {'VpcId': 'vpc-123', 'State': 'available', 'CidrBlock': '10.0.0.0/16'}
        subnet = {'SubnetId': 'subnet-123', 'VpcId': 'vpc-123', 'State': 'available',
                  'CidrBlock': '10.0.1.0/24', 'AvailabilityZone': 'us-east-1a',
                  'AvailabilityZoneId': 'use1-az1', 'AvailableIpAddressCount': 200}
        zone = {'Id': '/hostedzone/ZTEST', 'Name': 'test.automq.internal.', 'Config': {'PrivateZone': True}}
        trust = {'Statement': [{'Effect': 'Allow', 'Principal': {'Service': 'ec2.amazonaws.com'}, 'Action': 'sts:AssumeRole'}]}
        roles = [{'RoleName': n, 'Arn': f'arn:aws:iam::123456789012:role/{n}', 'AssumeRolePolicyDocument': trust} for n in ['cluster', 'console']]
        calls = []
        class FakeAWS:
            def __init__(self, region): self.region = region
            def read(self, service, op, *args):
                calls.append((service, op))
                self_args = list(args)
                if op == 'get-caller-identity': return {'Account': '123456789012'}
                if op == 'describe-vpcs': return {'Vpcs': [vpc]}
                if op == 'describe-subnets': return {'Subnets': [subnet]}
                if op == 'describe-route-tables': return {'RouteTables': [{'RouteTableId': 'rtb-test', 'Associations': [{'Main': True}]}]}
                if op == 'describe-vpc-endpoints': return {'VpcEndpoints': [{'VpcEndpointId': 'vpce-test', 'VpcId': 'vpc-123', 'ServiceName': 'com.amazonaws.us-east-1.s3', 'VpcEndpointType': 'Gateway', 'State': 'available', 'RouteTableIds': ['rtb-test']}]}
                if op == 'describe-vpc-attribute': return {'EnableDnsHostnames': {'Value': True}, 'EnableDnsSupport': {'Value': True}}
                if op == 'describe-instance-type-offerings': return {'InstanceTypeOfferings': [{'InstanceType': 't3.large' if 'Name=instance-type,Values=t3.large' in args else 'r6i.large'}]}
                if op == 'describe-images': return {'Images': [{'ImageId': 'ami-test', 'RootDeviceName': '/dev/xvda', 'Architecture': 'x86_64', 'State': 'available'}]}
                if op == 'list-hosted-zones-by-vpc': return {'HostedZoneSummaries': [{'HostedZoneId': 'ZTEST', 'Name': zone['Name']}]}
                if op == 'get-hosted-zone': return {'HostedZone': zone, 'VPCs': [{'VPCId': 'vpc-123', 'VPCRegion': 'us-east-1'}]}
                if op == 'describe-security-groups': return {'SecurityGroups': [{'GroupId': 'sg-test', 'GroupName': 'console', 'VpcId': 'vpc-123', 'IpPermissions': [{'IpProtocol': 'tcp', 'FromPort': port, 'ToPort': port, 'IpRanges': [{'CidrIp': '10.0.0.0/16'}]} for port in [22, 8080]], 'IpPermissionsEgress': [{'IpProtocol': '-1', 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}]}]}
                if op == 'describe-key-pairs': return {'KeyPairs': [{'KeyName': 'test-key', 'KeyPairId': 'key-test'}]}
                if op == 'get-parameter': return {'Parameter': {'Value': 'ami-test'}}
                if op == 'list-roles': return {'Roles': roles}
                if op == 'get-role': return {'Role': next(r for r in roles if r['RoleName'] == self_args[self_args.index('--role-name') + 1])}
                if op == 'list-instance-profiles-for-role': return {'InstanceProfiles': [{'Arn': 'arn:aws:iam::123456789012:instance-profile/test'}]}
                if op == 'list-attached-role-policies': return {'AttachedPolicies': []}
                raise AssertionError((service, op, args))
        data = {'environmentId': 'env-test', 'clientId': 'id', 'clientSecret': 'TEST_SECRET_VALUE', 'region': 'us-east-1', 'opsBucket': {'bucketName': 'automq-ops-test'}}
        encoded = base64.b64encode(json.dumps(data).encode()).decode()
        home = f'docker run -e CONFIG={encoded} -e CLOUD_PROVIDER=aws automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws'
        answers = iter(['1', '1', 'test-story', '1', 'yes', '1', '1', '1', 'yes', 'yes', '', 'c', 'r', '1', 'yes', '1', 'yes', '1', 'yes', '2', 'yes', 'yes'])
        output = []
        with tempfile.TemporaryDirectory() as temp, patch('setup.read_home_command', return_value=home), patch('getpass.getpass', return_value='TEST_PASSWORD_VALUE'):
            path = Path(temp) / 'out'
            wizard = Wizard(path, UI(lambda _: next(answers), output.append), FakeAWS, home_reader=lambda _: {'available': True, 'subscriptionState': 'Trial'})
            state = wizard.run()
            self.assertEqual(json.loads((path / 'cluster-request.json').read_text())['spec']['instanceRole'], 'cluster')
            for file in path.glob('*.sh'):
                subprocess.run(['bash', '-n', str(file)], check=True)
            for file in path.iterdir():
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            for secret in [encoded, data['clientSecret'], 'TEST_PASSWORD_VALUE']:
                self.assertNotIn(secret, '\n'.join(output))
                self.assertNotIn(secret, (path / 'review.json').read_text())
            launch = (path / 'prepare-console-ec2.sh').read_text()
            self.assertIn('ec2 run-instances', launch)
            self.assertIn('--no-associate-public-ip-address', launch)
            self.assertIn('DataVolumeId:BlockDeviceMappings', launch)
            self.assertNotIn(encoded, launch)
            devices = json.loads((path / 'console-devices.json').read_text())
            data = next(item['Ebs'] for item in devices if item['DeviceName'] == '/dev/sdf')
            self.assertTrue(data['Encrypted'])
            self.assertFalse(data['DeleteOnTermination'])
            unit = (path / 'automq-console.service').read_text()
            self.assertIn('RequiresMountsFor=/data', unit)
            self.assertIn('--network=host', unit)
            self.assertIn('src=/data/automq-console,dst=/root', unit)
            self.assertIn('automq-byoc-console:8.4.7-aws', unit)
            install = (path / 'install-console.sh').read_text()
            self.assertIn('SETUP_VOLUME_ID=${1:', install)
            self.assertIn('wipefs --no-act --noheadings --output TYPE', install)
            self.assertIn('CONFIG=' + encoded, (path / 'runtime.env').read_text())
            for service, op in calls:
                self.assertIn(op, AWS.ALLOWED[service])
            self.assertIn(('ec2', 'describe-route-tables'), calls)
            self.assertTrue(state['service_access']['userConfirmed'])
            self.assertIn('describe-vpc-endpoints', AWS.ALLOWED['ec2'])
            self.assertNotIn('routes', state['network'])

class OfflineCurlTests(unittest.TestCase):
    def test_generated_curl_posts_the_reviewed_request(self):
        from cmp_sign import signature
        from model import load_instance_configs

        requests = []

        class Console(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                requests.append((self.path, self.headers, body))
                self.send_response(201)
                self.end_headers()
                self.wfile.write(b'{"instanceId":"test-instance"}')

            def log_message(self, *args):
                pass

        with tempfile.TemporaryDirectory() as temp, HTTPServer(('127.0.0.1', 0), Console) as server:
            path = Path(temp)
            overrides = path / 'overrides.json'
            overrides.write_text('{"num.network.threads":"8","log.retention.ms":"604800000"}')
            state = fixture()
            state['home']['image'] = 'automq.azurecr.io/automq/automq-byoc-console:8.4.13-aws'
            state['instance_configs'] = load_instance_configs(overrides)
            state['api_credentials'] = {'accessKey': 'TestAccessKey1234', 'secretKey': 'TestSecretKey12345678901234567890'}
            export(path, state)
            origin = f'http://127.0.0.1:{server.server_port}'
            result = subprocess.run(
                ['bash', str(path / 'generate-curl.sh'), origin, 'signed'],
                capture_output=True, text=True, check=True, timeout=15,
            )
            self.assertEqual(requests, [])
            command = next(line for line in result.stdout.splitlines() if line.startswith('umask 077 && curl '))
            worker = Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                bundle = path / 'signed'
                proxy_env = {**os.environ, 'no_proxy': '127.0.0.1', 'NO_PROXY': '127.0.0.1'}
                subprocess.run(['bash', '-c', command], cwd=bundle, env=proxy_env, check=True, timeout=15)
                self.assertEqual(json.loads((bundle / 'create-response.json').read_bytes())['instanceId'], 'test-instance')
            finally:
                server.shutdown()
                worker.join()

            [(route, headers, body)] = requests
            self.assertEqual(route, '/api/v1/instances')
            self.assertEqual(body, (path / 'cluster-request.json').read_bytes())
            parsed = json.loads(body)
            self.assertEqual(parsed['version'], '5.5.9')
            self.assertEqual(parsed['features']['instanceConfigs'], [
                {'key': 'num.network.threads', 'value': '8'},
                {'key': 'log.retention.ms', 'value': '604800000'},
            ])
            date = datetime.strptime(headers['X-automq-date'], '%Y%m%dT%H%M%SZ').replace(tzinfo=timezone.utc)
            _, expected = signature(body, state['api_credentials']['accessKey'], state['api_credentials']['secretKey'], date)
            self.assertEqual(headers['Authorization'], expected)

    def test_invalid_instance_configs_stop_before_creating_output(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            source = path / 'overrides.json'
            output = path / 'out'
            for invalid in ['[1]', '{"log.retention.ms": 604800000}', '{"key":"1","key":"2"}']:
                with self.subTest(invalid=invalid):
                    source.write_text(invalid)
                    result = subprocess.run(
                        [sys.executable, str(Path(__file__).resolve().parents[1] / 'setup.py'),
                         '--instance-configs', str(source), '--output', str(output)],
                        capture_output=True, text=True, check=False, timeout=15,
                    )
                    self.assertEqual(result.returncode, 1)
                    self.assertIn('config', result.stderr.lower())
                    self.assertFalse(output.exists())

    def test_offline_bundle_is_portable_without_secret(self):
        from unittest.mock import patch
        from cmp_sign import generate_bundle
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            request = path / 'input.json'
            request.write_text('{"name":"test-cluster"}\n')
            credential = path / 'credentials.json'
            credential.write_text(json.dumps({'accessKey': 'TestAccessKey1234', 'secretKey': 'TestSecretKeyNotToTransfer12345678'}))
            output = path / 'signed'
            with patch('subprocess.run', side_effect=AssertionError('Generation must not execute commands')), patch('socket.socket.connect', side_effect=AssertionError('Generation must not connect')):
                generate_bundle('http://cmp.internal:8080', request, credential, output)
            self.assertEqual((output / 'request.json').read_bytes(), request.read_bytes())
            config = (output / 'request.curl').read_text()
            self.assertIn('data-binary = "@request.json"', config)
            self.assertIn('http://cmp.internal:8080/api/v1/instances', config)
            self.assertNotIn(str(path), config)
            for file in output.iterdir():
                self.assertNotIn('TestSecretKeyNotToTransfer12345678', file.read_text())
                self.assertEqual(file.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('python', (output / 'create-cluster.sh').read_text())
            subprocess.run(['bash', '-n', str(output / 'create-cluster.sh')], check=True)
            request.write_text('modified')
            self.assertEqual((output / 'request.json').read_text(), '{"name":"test-cluster"}\n')

    def test_placeholder_does_not_produce_executable_bundle(self):
        from cmp_sign import generate_bundle
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            (path / 'request.json').write_text('{}')
            (path / 'credentials.json').write_text(json.dumps({'accessKey': 'REPLACE_CMP_ACCESS_KEY', 'secretKey': 'REPLACE_CMP_SECRET_KEY'}))
            with self.assertRaises(ValueError):
                generate_bundle('http://cmp.internal:8080', path / 'request.json', path / 'credentials.json', path / 'out')
            self.assertFalse((path / 'out').exists())

class CreationPrerequisiteTests(unittest.TestCase):
    def test_subscription_error_is_explained_without_retry(self):
        from cmp_sign import generate_bundle
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            (path / 'request.json').write_text('{}')
            (path / 'credentials.json').write_text(json.dumps({'accessKey': 'TestAccessKey1234', 'secretKey': 'TestSecretKey12345678901234567890'}))
            bundle = generate_bundle('http://cmp.internal:8080', path / 'request.json', path / 'credentials.json', path / 'bundle')
            tools = path / 'bin'
            tools.mkdir()
            curl = tools / 'curl'
            curl.write_text('#!/bin/sh\nprintf \'{ "error": { "code": "Instance.NoAvailableSubscription" } }\' > create-response.json\necho called >> calls\nexit 22\n')
            curl.chmod(0o700)
            result = subprocess.run(['bash', str(bundle / 'create-cluster.sh')], capture_output=True, text=True, env={**os.environ, 'PATH': str(tools) + ':' + os.environ['PATH']})
            self.assertEqual(result.returncode, 22)
            self.assertIn('Home ACTIVE does not prove subscription availability', result.stderr)
            self.assertEqual((bundle / 'calls').read_text(), 'called\n')
            self.assertIn('about 60 seconds', (bundle / 'BEFORE-CREATE.md').read_text())

class HomeSubscriptionTests(unittest.TestCase):
    def test_subscription_states_match_cmp_prerequisite(self):
        from home import subscription_status
        self.assertTrue(subscription_status({'state': 'Trial'})['available'])
        self.assertTrue(subscription_status({'state': 'Active', 'activePayment': {'state': 'Valid'}})['available'])
        for body in [None, {}, {'state': 'Expired'}, {'state': 'Active', 'activePayment': {'state': 'Invalid'}}]:
            with self.assertRaises(SetupError):
                subscription_status(body)

    def test_missing_subscription_stops_before_cloud_queries(self):
        from unittest.mock import patch
        from home import subscription_status
        data = {'environmentId': 'env-test', 'clientId': 'id', 'clientSecret': 'secret', 'region': 'us-east-1', 'opsBucket': {'bucketName': 'automq-ops-test'}}
        encoded = base64.b64encode(json.dumps(data).encode()).decode()
        command = f'docker run -e CONFIG={encoded} -e CLOUD_PROVIDER=aws automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws'
        class NoCloud:
            def __init__(self, region): self.region = region
            def read(self, *args): raise AssertionError('Cloud discovery must follow the Home prerequisite')
        inputs = iter(['1'])
        def read(_):
            try: return next(inputs)
            except StopIteration: raise EOFError()
        with tempfile.TemporaryDirectory() as temp, patch('setup.read_home_command', return_value=command):
            wizard = Wizard(Path(temp) / 'out', UI(read, lambda _: None), NoCloud, home_reader=lambda _: subscription_status(None))
            with self.assertRaises(EOFError): wizard.run()
            self.assertEqual(list(wizard.directory.iterdir()), [])
