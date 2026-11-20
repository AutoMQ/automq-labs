#!/usr/bin/env python3
"""Interactive AWS AutoMQ setup. Cloud queries are read-only; preparation commands are user-executed."""
import argparse
from copy import deepcopy
import getpass
import ipaddress
import json
from pathlib import Path
import re
import shlex
import sys
import uuid
from core import (AWS, Back, SetupError, export, name_of, parse_home, policies,
                  new_api_credentials, role_commands, aws_command, tags, validate_console_sg, validate_network, validate_role, write_private, zone_commands)


from console import generate_console
from home import read_subscription
from endpoints import inspect_endpoints, s3_command
from progress import ReportingAWS, operation
from display import Display


class RetryNode(Exception):
    pass


def read_home_command():
    """Keep echo disabled for the whole paste, without flushing queued lines."""
    import termios
    if not sys.stdin.isatty():
        raise SetupError('Use an interactive terminal to paste the Home command securely.')
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    hidden = old[:]
    hidden[6] = old[6][:]
    # macOS canonical input also truncates long pasted lines; buffer lines here.
    hidden[3] &= ~(termios.ECHO | termios.ECHONL | termios.ICANON)
    hidden[6][termios.VMIN] = 1
    hidden[6][termios.VTIME] = 0
    lines = []
    characters = []
    try:
        termios.tcsetattr(fd, termios.TCSANOW, hidden)
        print('Docker command (hidden; press Enter on an empty line to finish):')
        print('> ', end='', flush=True)
        while True:
            char = sys.stdin.read(1)
            if not char or char == '\x04':
                raise EOFError()
            if char in ('\x7f', '\b'):
                if characters:
                    characters.pop()
                continue
            if char != '\n':
                characters.append(char)
                continue
            line = ''.join(characters)
            characters = []
            if line.strip() == 'b':
                raise Back()
            if not line.strip():
                return '\n'.join(lines)
            lines.append(line.rstrip('\r\n'))
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, old)
        print()


class UI:
    def __init__(self, read=input, show=print):
        self.read = read
        self.show = Display() if show is print else show

    def heading(self, title, step=False):
        if hasattr(self.show, 'heading'):
            self.show.heading(title, step)
        else:
            self.show('')
            self.show(title)
            self.show('')

    def section(self, title):
        self.heading(title)

    def prompt(self, text, current=None):
        self.show('b. Back')
        self.show('')
        self.show(text)
        if current is not None:
            self.show(f'Current/default: {current} (Enter to keep)')
        value = self.read('> ').strip()
        if value.lower() == 'b':
            raise Back()
        return current if not value and current is not None else value

    def confirm(self, text):
        while True:
            self.section('Confirmation')
            self.show(text)
            self.show('')
            self.show('yes. Confirm and continue')
            try:
                value = self.prompt('Enter yes to confirm, or b to go back. Enter alone does not confirm.')
            except Back:
                raise RetryNode() from None
            if value == 'yes':
                return
            self.show('Explicit confirmation is required; Enter does not confirm.')

    def preparation(self, path, back_label='Back to resource list'):
        path = Path(path)
        self.section('Preparation command')
        self.show('Run in another terminal. This guide does not execute the command.')
        self.show('')
        self.show(path.read_text().rstrip())
        self.show('')
        self.show(f'Command file: {path}')
        self.show(f'Run file: bash {shlex.quote(str(path))}')
        self.show('')
        self.show('r. Refresh resources after executing the command')
        self.show(f'b. {back_label}')
        while True:
            choice = self.read('> ').strip().lower()
            if choice in ('r', 'b'):
                return choice
            self.show('Enter r to refresh, or b to return.')

    def choose(self, text, fetch, label, identity, current=None, prepare=None, refresh=True):
        page = 0
        while True:
            try:
                rows = fetch()
            except SetupError as e:
                self.show(str(e))
                self.show('r. Retry')
                choice = self.prompt('Select')
                if choice == 'r':
                    continue
                continue
            while True:
                self.section(text)
                if current:
                    self.show(f'Current: {label(current)}')
                if prepare:
                    self.show('c. Show preparation command')
                if not rows:
                    self.show('No resources found.')
                for index, row in enumerate(rows[page * 20:(page + 1) * 20], page * 20 + 1):
                    self.show(f'{index}. {label(row)}')
                self.show('')
                if (page + 1) * 20 < len(rows):
                    self.show('n. Next page')
                if page > 0:
                    self.show('p. Previous page')
                if refresh:
                    self.show('r. Refresh')
                choice = self.prompt('Enter a resource number, exact ID/name or action letter.', identity(current) if current else None)
                if choice == 'r' and refresh:
                    page = 0
                    break
                if choice == 'n':
                    page = min(page + 1, max(0, (len(rows) - 1) // 20))
                elif choice == 'p':
                    page = max(0, page - 1)
                elif choice == 'c' and prepare:
                    if self.preparation(prepare()) == 'r':
                        page = 0
                        break
                else:
                    found = next((row for row in rows if identity(row) == choice), None)
                    if found is None and str(choice).isdigit() and 1 <= int(choice) <= len(rows):
                        found = rows[int(choice) - 1]
                    if found is not None:
                        self.show(f'\nSelected: {label(found)}')
                        return found
                    self.show('Select a displayed resource by number or exact identifier.')


class Wizard:
    NODE_TITLES = {
        'console_choice': 'Choose Console', 'home': 'Home environment command',
        'context': 'Choose VPC', 'cluster_name': 'Cluster name',
        'peak': 'Expected peak BytesIn', 'target': 'Cluster configuration',
        'network': 'Choose compute subnet', 'instance_type': 'Choose instance type',
        'dns': 'Private DNS', 'data_bucket': 'Data Bucket', 'cluster_sg': 'Cluster security group',
        'console_source': 'Console access source', 'console_sg': 'Console security group',
        'console_key': 'Console SSH key pair', 'console_password': 'Console initial admin password',
        'existing_console_subnet': 'Existing Console subnet',
        'service_access': 'VPC service access dependencies',
        'cluster_identity': 'AutoMQ Cluster Role', 'console_identity': 'Console Role',
        'review': 'Review and generate commands',
    }
    NEW_CONSOLE_NODES = {'console_source', 'console_sg', 'console_key', 'console_password'}

    def node_enabled(self, node):
        if node in self.NEW_CONSOLE_NODES:
            return self.state.get('console_mode') == 'new'
        if node == 'existing_console_subnet':
            return self.state.get('console_mode') == 'existing'
        return True

    def __init__(self, directory, ui=None, aws_factory=AWS, home_reader=read_subscription):
        self.directory = Path(directory).resolve()
        # A new output directory prevents stale downstream artifacts surviving Back or a rerun.
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=False)
        self.ui = ui or UI()
        self.aws_factory = lambda region: ReportingAWS(aws_factory(region), self.ui.show)
        self.home_reader = home_reader
        self.state = {}
        self.nodes = list(self.NODE_TITLES)
        self.snapshots = []
        self.artifact_owners = {}

    def run(self):
        initial_state = deepcopy(self.state)
        index = 0
        while index < len(self.nodes):
            try:
                if not self.node_enabled(self.nodes[index]):
                    self.snapshots.append(deepcopy(self.state))
                    index += 1
                    continue
                visible_nodes = [node for node in self.nodes[:index + 1]
                                 if self.node_enabled(node)]
                title = self.NODE_TITLES.get(self.nodes[index], self.nodes[index])
                self.ui.heading(f'Step {len(visible_nodes)} | {title}', step=True)
                before = {p: p.read_bytes() for p in self.directory.rglob('*') if p.is_file()}
                try:
                    getattr(self, self.nodes[index])()
                finally:
                    for p in self.directory.rglob('*'):
                        if p.is_file() and (p not in before or p.read_bytes() != before[p]):
                            self.artifact_owners[p] = index
                self.snapshots = self.snapshots[:index]
                self.snapshots.append(deepcopy(self.state))
                index += 1
            except Back:
                index = max(0, index - 1)
                while index > 0 and not self.node_enabled(self.nodes[index]):
                    index -= 1
                # Keep the target node's prior selection, discard every later result.
                self.state = deepcopy(self.snapshots[index] if index < len(self.snapshots) else initial_state)
                self.snapshots = self.snapshots[:index + 1]
                for path, owner in list(self.artifact_owners.items()):
                    if owner > index:
                        path.unlink(missing_ok=True)
                        del self.artifact_owners[path]
                self.aws = self.aws_factory(self.state['home']['region']) if 'home' in self.state else None
                self.ui.show('Back: later selections and confirmations have been cleared.')
            except RetryNode:
                self.ui.show('Returned to the current node; confirmation was not retained.')
            except SetupError as e:
                self.ui.show(f'\nERROR: {e}\n')
        return self.state

    def console_choice(self):
        self.ui.show('Configure the Console environment before preparing cluster resources.')
        self.ui.section('Choose Console')
        self.ui.show('1. Install new EC2 Console (default)')
        self.ui.show('2. Use existing Console')
        mode = self.ui.prompt('Select', '2' if self.state.get('console_mode') == 'existing' else '1')
        if mode not in ['1', '2']:
            raise SetupError('Choose 1 or 2.')
        self.state['console_mode'] = 'new' if mode == '1' else 'existing'

    def home(self):
        self.ui.show('Provide the Home command to identify the environment, Region and Ops Bucket. The command is parsed locally, not executed.')
        if 'home' in self.state:
            self.ui.show('Home command: provided (hidden).')
            if self.ui.prompt('Enter to keep, or paste to replace') == '':
                self.check_subscription()
                return
        while True:
            self.ui.show('Paste the complete Home Docker command, including all lines. Input is hidden; nothing is executed. After pasting, press Enter on an empty line to finish. Enter b to go back.')
            command = read_home_command()
            try:
                self.state['home'] = parse_home(command)
                break
            except SetupError as e:
                self.ui.show(f'\nERROR: {e}\nConsole selection kept. Paste the complete command again.\n')
        self.aws = self.aws_factory(self.state['home']['region'])
        self.check_subscription()

    def check_subscription(self):
        self.ui.show('Checking the environment UsageBased subscription with Home. No Console connection is required.')
        with operation(self.ui.show, 'Checking: Home subscription'):
            self.state['subscription'] = self.home_reader(self.state['home'])
        self.ui.show('Home reports an available subscription or trial. After Console installation, still wait for Home ACTIVE and CMP subscription refresh before executing curl.')

    def context(self):
        self.aws = self.aws_factory(self.state['home']['region'])
        account = self.aws.read('sts', 'get-caller-identity')['Account']
        self.state['account'] = account
        self.ui.show(f'Account: {account}; Region: {self.aws.region}')
        self.state['vpc'] = self.ui.choose('Select VPC', lambda: self.aws.read('ec2', 'describe-vpcs')['Vpcs'],
            lambda x: f'{name_of(x)} | {x["VpcId"]} | {x["CidrBlock"]}', lambda x: x['VpcId'], self.state.get('vpc'))
        if self.state['console_mode'] == 'existing':
            self.ui.confirm('Confirm the existing Console manages this same VPC. Its address and credentials are not collected by the guide.')

    def cluster_name(self):
        self.ui.show('Choose a name to identify this cluster and its preparation resources.')
        name = self.ui.prompt('Cluster name (3–24 lowercase letters, digits or hyphens)', self.state.get('name', 'test-' + uuid.uuid4().hex[:8]))
        if not re.fullmatch(r'[a-z][a-z0-9-]{2,23}', name):
            raise SetupError('Use 3–24 lowercase letters, digits or hyphens, starting with a letter.')
        self.state['name'] = name

    def peak(self):
        self.ui.show('Provide the expected peak ingestion rate for capacity planning.')
        peak = self.ui.prompt('Expected peak BytesIn in MiB/s (1 MiB = 1,048,576 bytes)', self.state.get('peak'))
        try:
            peak = float(peak)
            if not 0 < peak < float('inf'):
                raise ValueError()
        except (ValueError, TypeError):
            raise SetupError('Enter a finite positive peak BytesIn.') from None
        self.state['peak'] = peak

    def target(self):
        self.ui.show('AutoMQ 5.5.6 | EC2 | 3 total nodes | UsageBased | ON_DEMAND | EBSWAL | SASL_PLAINTEXT:9102 | CPMK')
        self.ui.confirm('Schema Registry and metrics export are off. Table Topic is disabled. Continue with this first test story?')

    def network(self):
        self.ui.show('Choose the subnet where the single-AZ cluster will run.')
        vpc = self.state['vpc']
        subnet = self.ui.choose('Select single-AZ compute subnet',
            lambda: self.aws.read('ec2', 'describe-subnets', '--filters', f'Name=vpc-id,Values={vpc["VpcId"]}')['Subnets'],
            lambda x: f'{name_of(x)} | {x["SubnetId"]} | {x["CidrBlock"]} | {x["AvailabilityZone"]} | free IPs: {x["AvailableIpAddressCount"]}',
            lambda x: x['SubnetId'], self.state.get('subnet'))
        self.state['subnet'] = subnet
        with operation(self.ui.show, 'Checking: selected subnet and VPC DNS'):
            self.state['network'] = validate_network(self.aws, vpc, subnet)
        self.ui.section('Subnet checks')
        self.ui.show(f'PASS: VPC DNS enabled; subnet belongs to this VPC; {subnet["AvailableIpAddressCount"]} IPs available.')

    def instance_type(self):
        self.ui.show('Choose an EBSWAL instance type available in the selected AZ.')
        subnet = self.state['subnet']
        offerings = self.aws.read('ec2', 'describe-instance-type-offerings', '--location-type', 'availability-zone',
            '--filters', f'Name=location,Values={subnet["AvailabilityZone"]}', 'Name=instance-type,Values=r6i.large,r6in.large')['InstanceTypeOfferings']
        if not offerings:
            raise SetupError('Neither selected catalog machine type is offered in this AZ. Select another subnet.')
        self.state['instance_type'] = self.ui.choose('Select instance type (catalog-supported EBSWAL types)', lambda: offerings,
            lambda x: x['InstanceType'], lambda x: x['InstanceType'], {'InstanceType': self.state['instance_type']} if 'instance_type' in self.state else None, refresh=False)['InstanceType']
        images = self.aws.read('ec2', 'describe-images', '--filters', 'Name=name,Values=AutoMQ-automq-kafka-Prod-5.5.6-x86_64', 'Name=state,Values=available')['Images']
        if not images:
            raise SetupError('No accessible AutoMQ 5.5.6 x86_64 AMI. Resolve image availability before continuing.')
        self.ui.section('Resource checks')
        self.ui.show('PASS: Selected instance type is offered in this AZ; AutoMQ 5.5.6 AMI is accessible.')

    def existing_console_subnet(self):
        self.ui.show('Choose the existing Console subnet to check its S3 Gateway Endpoint association.')
        self.state['console_subnet'] = self.ui.choose('Existing Console subnet',
            lambda: self.aws.read('ec2', 'describe-subnets', '--filters', f'Name=vpc-id,Values={self.state["vpc"]["VpcId"]}')['Subnets'],
            lambda x: f'{name_of(x)} | {x["SubnetId"]} | {x["CidrBlock"]} | {x["AvailabilityZone"]}',
            lambda x: x['SubnetId'], self.state.get('console_subnet'))

    def service_access(self):
        self.ui.show('S3 must use a Gateway Endpoint covering the Console and cluster subnet route tables. Other AWS services may use Interface Endpoints or your existing access paths.')
        subnet_ids = [self.state['subnet']['SubnetId']]
        if self.state['console_mode'] == 'existing':
            subnet_ids.append(self.state['console_subnet']['SubnetId'])
        # The new EC2 Console in this story uses the selected compute subnet.
        while True:
            result = inspect_endpoints(self.aws, self.state['vpc']['VpcId'], subnet_ids)
            command = s3_command(self.directory, self.state, result)
            self.ui.section('S3 Gateway Endpoint — required')
            for subnet, table in result['subnetRouteTables'].items():
                self.ui.show(f'{subnet} -> {table}')
            for endpoint in result['s3Gateways']:
                self.ui.show(f'Available: {endpoint["VpcEndpointId"]} | route tables: {", ".join(endpoint.get("RouteTableIds", []))}')
            if result['s3MissingRouteTables']:
                self.ui.show('Missing S3 Gateway coverage: ' + ', '.join(result['s3MissingRouteTables']))
                if command:
                    self.ui.show('A new endpoint uses the AWS default endpoint policy. Existing endpoint policies are preserved.')
                    self.ui.preparation(command, back_label='Back to endpoint checks')
                    continue
                else:
                    for endpoint in result['s3Unready']:
                        self.ui.show(f'Endpoint {endpoint["id"]}: {endpoint["state"]}. Wait for availability or resolve its state; no duplicate creation command is generated.')
                self.ui.show('r. Refresh')
                self.ui.prompt('Enter r after preparing the endpoint, or b to go back.')
                continue
            self.ui.show('PASS: Available S3 Gateway Endpoints cover all required route tables.')
            policy_file = self.directory / 's3-endpoint-policy-review.json'
            write_private(policy_file, [{'id': e['VpcEndpointId'], 'policy': e.get('PolicyDocument')} for e in result['s3Gateways']])
            self.ui.show(f'Endpoint policies for review: {policy_file}')
            self.ui.section('Other AWS services — Interface Endpoints optional')
            for service in result['interfaces']:
                if not service['endpoints']:
                    self.ui.show(f'{service["service"]}: no matching Interface Endpoint found in this VPC ({service["serviceName"]}).')
                for endpoint in service['endpoints']:
                    self.ui.show(f'{service["service"]}: {endpoint["id"]} | {endpoint["state"]} | Private DNS: {endpoint["privateDnsEnabled"]}')
            self.ui.show('\nAn endpoint record does not prove connectivity. Without a suitable endpoint, provide access to the corresponding AWS API through an outbound or enterprise private path. Pricing is used by CMP recommendations/automatic instance selection.')
            self.ui.show('Console also needs outbound HTTPS to Home and the current image/artifact repositories; AWS endpoints do not cover these addresses.')
            self.ui.confirm('Confirm S3 endpoint policies permit the Ops/Data Buckets and required operations, and the other service access requirements are satisfied. Effective permissions and connectivity are not tested.')
            result['userConfirmed'] = True
            self.state['service_access'] = result
            return

    def dns(self):
        self.ui.show('Private DNS resolves cluster addresses within the VPC; this story uses no TLS certificates.')
        zone = self.ui.choose('Select private hosted zone',
            lambda: self.aws.read('route53', 'list-hosted-zones-by-vpc', '--vpc-id', self.state['vpc']['VpcId'], '--vpc-region', self.aws.region)['HostedZoneSummaries'],
            lambda x: f'{x["Name"]} | {x["HostedZoneId"]}', lambda x: x['HostedZoneId'],
            prepare=lambda: zone_commands(self.directory, self.state))
        detail = self.aws.read('route53', 'get-hosted-zone', '--id', zone['HostedZoneId'])
        if not detail['HostedZone']['Config']['PrivateZone'] or not any(v['VPCId'] == self.state['vpc']['VpcId'] and v['VPCRegion'] == self.aws.region for v in detail.get('VPCs', [])):
            raise SetupError('Select a private hosted zone associated with this VPC and Region.')
        self.state['zone'] = detail['HostedZone']

    def data_bucket(self):
        self.ui.confirm('Data Bucket: CMP creates automq-data-*. Console Policy needs CreateBucket, tagging and reads. Cluster Policy allows data-object access under that prefix in this account. Confirm CMP management.')

    def cluster_sg(self):
        self.ui.confirm('Cluster SG: CMP creates and manages it. Console Policy needs CreateSecurityGroup, ingress/egress and tag permissions. SASL_PLAINTEXT uses TCP 9102; internal rules use the VPC CIDR. Confirm CMP management.')

    def console_source(self):
        self.ui.show('New EC2 Console: t3.large, private IP, chosen Console subnet, 20 GiB root + 20 GiB data, XFS /data.')
        cidr = self.ui.prompt('CIDR allowed to reach Console TCP 22 and 8080 through your private management route',
                              self.state.get('console_source', self.state['vpc']['CidrBlock']))
        try:
            network = ipaddress.ip_network(cidr, strict=True)
            if network.version != 4 or network.prefixlen == 0:
                raise ValueError()
        except ValueError:
            raise SetupError('Use a specific IPv4 CIDR; the guide does not open Console to 0.0.0.0/0.') from None
        self.state['console_source'] = cidr

    def console_sg(self):
        self.ui.show('Choose the security group that permits your configured Console management access.')
        cidr = self.state['console_source']
        def prepare_sg():
            region, name = self.aws.region, 'automq-setup-' + self.state['name'] + '-console-sg'
            spec = [{'ResourceType': 'security-group', 'Tags': [{'Key': 'Name', 'Value': name}] + tags(self.state['name'], 'console-sg')}]
            write_private(self.directory / 'console-sg-tags.json', spec)
            create = aws_command(region, 'ec2', 'create-security-group', '--group-name', name, '--description', 'AutoMQ Console test access',
                                 '--vpc-id', self.state['vpc']['VpcId'], '--tag-specifications', 'file://console-sg-tags.json', '--query', 'GroupId', '--output', 'text')
            lines = ['#!/usr/bin/env bash', 'set -euo pipefail', 'cd -- "$(dirname -- "$0")"', 'SETUP_SG_ID=$(' + create + ')']
            for port in [22, 8080]:
                lines.append(aws_command(region, 'ec2', 'authorize-security-group-ingress', '--protocol', 'tcp', '--port', str(port), '--cidr', cidr) + ' --group-id "$SETUP_SG_ID"')
            lines.append('printf "%s\\n" "$SETUP_SG_ID"')
            path = self.directory / 'prepare-console-sg.sh'
            write_private(path, '\n'.join(lines) + '\n')
            return path
        sg = self.ui.choose('Select Console security group',
            lambda: self.aws.read('ec2', 'describe-security-groups', '--filters', f'Name=vpc-id,Values={self.state["vpc"]["VpcId"]}')['SecurityGroups'],
            lambda x: f'{x["GroupName"]} | {x["GroupId"]}', lambda x: x['GroupId'], self.state.get('console_security_group'), prepare=prepare_sg)
        with operation(self.ui.show, 'Checking: Console security group rules'):
            validate_console_sg(sg, self.state['vpc']['VpcId'], cidr)
        self.ui.section('Selected Console security group rules')
        self.ui.show(json.dumps({'ingress': sg['IpPermissions'], 'egress': sg['IpPermissionsEgress']}, indent=2))
        self.ui.confirm('Review Console SG: TCP 22 from your management source, TCP 8080 from your access source (or localhost SSH tunnel), and outbound HTTPS. Confirm your private SSH route and key are available.')
        self.state['console_security_group'] = sg

    def console_key(self):
        self.ui.show('Choose the SSH key pair for accessing the Console instance. Keep its private key locally.')
        key = self.ui.choose('Select SSH key pair (private key stays with you)', lambda: self.aws.read('ec2', 'describe-key-pairs')['KeyPairs'],
            lambda x: f'{x["KeyName"]} | {x["KeyPairId"]}', lambda x: x['KeyName'], self.state.get('console_key_pair'))
        self.state['console_key_pair'] = key
        ami_id = self.aws.read('ssm', 'get-parameter', '--name', '/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64')['Parameter']['Value']
        ami = self.aws.read('ec2', 'describe-images', '--image-ids', ami_id)['Images'][0]
        if ami['Architecture'] != 'x86_64' or ami['State'] != 'available':
            raise SetupError('The Console AMI must be available and x86_64.')
        offerings = self.aws.read('ec2', 'describe-instance-type-offerings', '--location-type', 'availability-zone', '--filters',
            f'Name=location,Values={self.state["subnet"]["AvailabilityZone"]}', 'Name=instance-type,Values=t3.large')['InstanceTypeOfferings']
        if not offerings:
            raise SetupError('t3.large is not offered in the selected Console AZ.')
        self.state['console_ami'] = ami

    def console_password(self):
        self.ui.show('Set the initial admin password for the new Console.')
        self.ui.section('Console initial admin password')
        self.ui.show('Input is hidden. Enter b to go back.')
        password = getpass.getpass('> ')
        if password == 'b':
            raise Back()
        if len(password) < 12 or any(c in password for c in '\r\n\x00'):
            raise SetupError('Use a password of at least 12 characters without line breaks.')
        self.state['console_config'] = {'security_group': self.state['console_security_group'], 'key_name': self.state['console_key_pair']['KeyName'], 'ami': self.state['console_ami'], 'password': password}

    def identity(self, key, purpose):
        self.ui.show(f'{purpose}: prepare an EC2-trusted Role and Instance Profile, or select an existing Role.')
        prepare = None
        if not (key == 'console_role' and self.state.get('console_mode') == 'existing'):
            prepare = lambda: role_commands(self.directory, self.aws.region, self.state['name'], purpose)
        role = self.ui.choose('Select Role', lambda: self.aws.read('iam', 'list-roles')['Roles'],
            lambda x: f'{x["RoleName"]} | {x["Arn"]}', lambda x: x['RoleName'], self.state.get(key), prepare=prepare)
        # Re-read only the selected Role; list attributes are not a validation result.
        role = self.aws.read('iam', 'get-role', '--role-name', role['RoleName'])['Role']
        if not (key == 'console_role' and self.state.get('console_mode') == 'existing'):
            with operation(self.ui.show, 'Checking: Role trust and instance profile'):
                self.state[key + '_profile'] = validate_role(self.aws, role, self.ui.show)
        self.state[key] = role

    def cluster_identity(self):
        self.identity('cluster_role', 'cluster-role')
        cluster, _ = policies(self.state)
        write_private(self.directory / 'cluster-role-policy-review.json', cluster)
        self.ui.section('Required AutoMQ Cluster Role Policy')
        self.ui.show(json.dumps(cluster, indent=2))
        self.ui.confirm('Review the required Cluster Role Policy and EC2 trust. Confirm you will grant missing permissions; this is not an effective-permissions check.')

    def console_identity(self):
        self.identity('console_role', 'console-role')
        arns = []
        for key in ['cluster_role', 'console_role']:
            arns += [p['PolicyArn'] for p in self.aws.read('iam', 'list-attached-role-policies', '--role-name', self.state[key]['RoleName'])['AttachedPolicies']]
        self.state['attached_policies'] = sorted(set(arns))
        _, console = policies(self.state)
        write_private(self.directory / 'console-role-policy-review.json', console)
        self.ui.section('Required Console Role Policy')
        self.ui.show(json.dumps(console, indent=2))
        self.ui.confirm('Review the required Console Role Policy and trust. Attach missing permissions incrementally; preserve existing attachments. Effective permissions are not checked.')

    def review(self):
        self.ui.show(f'Cluster: {self.state["name"]}; VPC: {self.state["vpc"]["VpcId"]}; subnet: {self.state["subnet"]["SubnetId"]}')
        self.ui.confirm('Confirm this plan. Final files contain exact resource identifiers. Creating the cluster is a later Console operation.')
        if self.state['console_mode'] == 'new':
            self.state['api_credentials'] = new_api_credentials()
            generate_console(self.directory, self.state)
        files = export(self.directory, self.state)
        self.ui.show(f'Created cluster-request.json and review.json in {self.directory}.')
        self.ui.show('Before executing curl: wait for Home ACTIVE and verify UsageBased subscription/trial availability. These are separate prerequisites; the guide has not checked them.')
        for path in files:
            self.ui.show(f'Authorization command (execute yourself): bash {path}')
        self.ui.show('Existing Console: fill cmp-credentials.json. Run generate-curl.sh locally with the Console URL as seen from the execution machine and a new output directory. Transfer only that signed bundle, then run its create-cluster.sh in the Console network. Generation sends no request.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, help='New local output directory (must not exist)')
    parser.add_argument('--instance-configs', type=Path, help='Optional JSON file mapping instance config keys to strings')
    args = parser.parse_args()
    try:
        from flows import AWSWizard
        from model import load_instance_configs
        configs = load_instance_configs(args.instance_configs) if args.instance_configs else {}
        wizard = AWSWizard(args.output)
        wizard.state['instance_configs'] = configs
        wizard.run()
    except (EOFError, KeyboardInterrupt):
        print('\nSetup stopped.', file=sys.stderr)
        return 130
    except (SetupError, OSError) as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
