"""Complete AWS decision flow. Cloud mutations are generated, never executed."""
import getpass
import ipaddress
import json
import re
import shlex
import uuid
from pathlib import Path
from urllib.parse import urlparse
from setup import Wizard
from core import Back, SetupError, aws_command, name_of, tags, write_private, validate_network
from model import cluster_version, filesystem, listeners
from progress import operation


class AWSWizard(Wizard):
    NODE_TITLES = {
        'console_choice': 'Choose Console', 'home': 'Home environment command', 'context': 'Choose VPC',
        'cluster_name': 'Cluster name', 'description': 'Cluster description', 'deployment': 'EC2 or EKS',
        'layout': 'Availability zones', 'network': 'Compute subnets', 'capacity': 'Node count',
        'peak': 'Expected peak BytesIn', 'wal': 'WAL storage', 'fs_type': 'File system type',
        'instance_type': 'Instance type', 'payment': 'EC2 purchase option', 'payment_term': 'Reserved term',
        'client_network': 'Application network', 'transport': 'Kafka transport', 'authentication': 'Kafka authentication',
        'dns_mode': 'DNS mode', 'dns': 'DNS resources', 'certificate': 'Server certificate',
        'private_key': 'Server private key', 'client_ca': 'Client CA certificate',
        'schema': 'Schema Registry', 'metrics_mode': 'Metrics export', 'metrics_target': 'Metrics destination',
        'custom_tags': 'Custom tags', 'eks_target': 'AutoMQ EKS cluster', 'workload_namespace': 'AutoMQ namespace', 'workload_serviceaccount': 'AutoMQ ServiceAccount', 'eks_capacity': 'EKS compute capacity',
        'eks_schedule': 'EKS scheduling', 'lb_subnets': 'Kafka NLB subnets', 'eks_prerequisites': 'EKS prerequisites',
        'data_bucket': 'Data Bucket', 'cluster_sg': 'Cluster security group',
        'fs_subnets': 'File system subnets', 'fs_sg': 'File system security group',
        'console_deployment': 'Console deployment', 'console_subnet': 'Console subnet',
        'console_source': 'Console access source', 'console_sg': 'Console security group',
        'console_key': 'Console SSH key pair', 'console_eks': 'Console EKS cluster', 'console_eks_subnets': 'Console EKS workload subnets',
        'console_password': 'Console initial admin password', 'service_access': 'VPC service access dependencies',
        'cluster_binding': 'AutoMQ workload identity', 'cluster_identity': 'AutoMQ Cluster Role',
        'console_binding': 'Console workload identity', 'console_identity': 'Console Role',
        'eks_access': 'Console access to AutoMQ EKS', 'review': 'Review and generate commands',
    }

    def console_choice(self):
        choice=self.option('Console environment',[('new','Install a new Console'),('existing','Use an existing Console')],self.state.get('console_mode'))
        self.state['console_mode']=choice

    def node_enabled(self, node):
        s = self.state
        eks = s.get('deploy_type') == 'K8S'
        new = s.get('console_mode') == 'new'
        console_eks = s.get('console_deploy') == 'K8S'
        rules = {'fs_type': s.get('wal') == 'FSWAL', 'fs_subnets': s.get('wal') == 'FSWAL' and s.get('filesystem', {}).get('fileSystemType') == 'EFS_PROVISIONED',
                 'fs_sg': s.get('wal') == 'FSWAL', 'payment': not eks,
                 'payment_term': not eks and s.get('payment', {}).get('paymentType') == 'RESERVED',
                 'certificate': s.get('dns_mode') == 'private' and 'tls' in s.get('transport', []),
                 'private_key': s.get('dns_mode') == 'private' and 'tls' in s.get('transport', []),
                 'client_ca': 'mtls' in s.get('auth', []), 'metrics_target': s.get('metrics_auth') != 'off',
                 'console_deployment': new, 'console_eks': new and console_eks, 'console_eks_subnets': new and console_eks,
                 'console_subnet': not (new and console_eks),
                 'console_source': new and not console_eks, 'console_sg': new and not console_eks,
                 'console_key': new and not console_eks, 'console_password': new,
                 'console_binding': new and console_eks,
                 'cluster_sg': not eks}
        for key in ['eks_target', 'workload_namespace', 'workload_serviceaccount', 'eks_capacity', 'eks_schedule', 'lb_subnets', 'eks_prerequisites', 'cluster_binding', 'eks_access']:
            rules[key] = eks
        return rules.get(node, True)

    def option(self, title, options, current=None):
        saved=self.state.setdefault('_choices',{})
        current=saved.get(title,current)
        choice=self.ui.choose(title, lambda: options, lambda x: x[1], lambda x: x[0],
                              next((x for x in options if x[0] == current), options[0]), refresh=False)[0]
        saved[title]=choice
        return choice

    def text(self, key, title, default=None):
        value = self.ui.prompt(title, self.state.get(key, default))
        self.state[key] = value
        return value

    def file(self, title):
        path = Path(self.ui.prompt(title)).expanduser()
        try:
            if path.stat().st_size > 1024 * 1024:
                raise SetupError('File is too large (maximum 1 MiB).')
            return path, path.read_text()
        except (OSError, UnicodeError):
            raise SetupError('Cannot read this text file. Check its path and permissions.') from None

    def secret(self, title):
        self.ui.show(title + ' (hidden; b to go back)')
        value = getpass.getpass('> ')
        if value == 'b': raise Back()
        if not value or any(c in value for c in '\r\n\x00'): raise SetupError('Enter a non-empty single-line value.')
        return value

    def multi(self, title, rows, label, current=None, count=None, fetch=None, prepare=None):
        previous=self.state.get('_multi_choices',{}).get(title)
        if previous and all(x in rows for x in previous):
            current=','.join(str(rows.index(x)+1) for x in previous)
        while True:
            self.ui.section(title)
            for i, row in enumerate(rows, 1): self.ui.show(f'{i}. {label(row)}')
            if fetch: self.ui.show('r. Refresh resources')
            if prepare: self.ui.show('c. Show preparation command')
            raw = self.ui.prompt('Enter numbers separated by commas (example: 1,2,3).', current)
            if raw == 'r' and fetch:
                rows = fetch()
                continue
            if raw == 'c' and prepare:
                if self.ui.preparation(prepare()) == 'r': rows = fetch()
                continue
            try:
                numbers = [int(x) for x in raw.split(',')]
                if len(set(numbers)) != len(numbers) or any(x < 1 or x > len(rows) for x in numbers): raise ValueError()
                if count and len(numbers) != count: raise ValueError()
            except (ValueError, AttributeError):
                raise SetupError(f'Select {count or "one or more"} distinct displayed options, separated by commas.') from None
            self.state.setdefault('_multi_choices',{})[title]=[rows[i-1] for i in numbers]
            return [rows[i-1] for i in numbers]

    def subnets(self, title, count=None, azs=None):
        def fetch():
            rows = self.aws.read('ec2', 'describe-subnets', '--filters', f'Name=vpc-id,Values={self.state["vpc"]["VpcId"]}')['Subnets']
            return [x for x in rows if x['AvailabilityZone'] in azs] if azs else rows
        def prepare():
            from resources import script
            zones = azs or [z['ZoneName'] for z in self.aws.read('ec2','describe-availability-zones','--filters','Name=state,Values=available')['AvailabilityZones']]
            zone = self.ui.choose('New subnet AZ',lambda:zones,str,str,refresh=False)
            raw = self.ui.prompt('New subnet IPv4 CIDR, within the VPC and not overlapping existing subnets')
            try: cidr = ipaddress.ip_network(raw,strict=True)
            except ValueError: raise SetupError('Enter a valid subnet CIDR.') from None
            if cidr.version != 4 or not 16 <= cidr.prefixlen <= 28 or not cidr.subnet_of(ipaddress.ip_network(self.state['vpc']['CidrBlock'])):
                raise SetupError('Subnet must be an IPv4 /16–/28 within the selected VPC CIDR.')
            all_subnets=self.aws.read('ec2','describe-subnets','--filters',f'Name=vpc-id,Values={self.state["vpc"]["VpcId"]}')['Subnets']
            if any(cidr.overlaps(ipaddress.ip_network(x['CidrBlock'])) for x in all_subnets): raise SetupError('CIDR overlaps an existing subnet.')
            name=f'automq-setup-{self.state["name"]}-{zone}-subnet'
            spec=[{'ResourceType':'subnet','Tags':[{'Key':'Name','Value':name}]+tags(self.state['name'],'subnet')}]
            return script(self.directory,'prepare-subnet.sh',[aws_command(self.aws.region,'ec2','create-subnet','--vpc-id',self.state['vpc']['VpcId'],'--availability-zone',zone,'--cidr-block',str(cidr),'--tag-specifications',json.dumps(spec))])
        selected = self.multi(title, fetch(), lambda x: f'{name_of(x)} | {x["SubnetId"]} | {x["CidrBlock"]} | {x["AvailabilityZone"]}', count=count, fetch=fetch, prepare=prepare)
        for subnet in selected: validate_network(self.aws, self.state['vpc'], subnet, min_ips=1)
        if len({x['AvailabilityZone'] for x in selected}) != len(selected): raise SetupError('Select at most one subnet per AZ.')
        if azs and {x['AvailabilityZone'] for x in selected} != set(azs): raise SetupError('Subnets must cover every selected AZ.')
        return selected

    def description(self):
        if len(self.text('description', 'Optional cluster description', '')) > 256: raise SetupError('Description must be at most 256 characters.')

    def deployment(self):
        self.state['deploy_type'] = self.option('Run AutoMQ on', [('IAAS', 'EC2'), ('K8S', 'EKS')], self.state.get('deploy_type'))

    def layout(self):
        self.state['az_count'] = int(self.option('Availability-zone layout', [('1', 'Single AZ'), ('3', 'Three AZs')], str(self.state.get('az_count', 1))))

    def network(self):
        self.ui.show('Choose one compute subnet per AZ. These subnets define the cluster placement.')
        selected = self.subnets('Compute subnets', self.state['az_count'])
        self.state.update(subnets=selected, subnet=selected[0], network={'dns': 'passed', 'connectivity': 'user review required'})

    def capacity(self):
        raw = self.ui.prompt('Total node count (at least 3; divisible by the AZ count)', self.state.get('node_count', 3))
        try: n = int(raw)
        except ValueError: raise SetupError('Enter an integer.') from None
        if n < 3 or n % self.state['az_count']: raise SetupError('Node count must be at least 3 and divisible by the AZ count.')
        if self.state['deploy_type']=='IAAS' and any(x['AvailableIpAddressCount'] < n//self.state['az_count'] for x in self.state['subnets']):
            raise SetupError('Selected subnets do not have enough free IPs for the requested EC2 nodes.')
        self.state['node_count'] = n

    def wal(self):
        options = [('EBSWAL', 'BLOCK — EBS WAL'), ('S3WAL', 'DIRECT — S3 WAL')]
        if self.state['az_count'] == 3: options.append(('FSWAL', 'FILE_SYSTEM — EFS / FSx'))
        self.state['wal'] = self.option('WAL storage', options, self.state.get('wal'))

    def fs_type(self):
        options = [('EFS_PROVISIONED', 'EFS')]
        if self.state['deploy_type'] == 'IAAS': options.append(('ONTAP_V2', 'FSx for ONTAP'))
        kind = self.option('File system', options)
        self.state['filesystem'] = filesystem(self.state['peak'], kind)
        self.ui.show(json.dumps(self.state['filesystem'], indent=2))
        self.ui.show('EFS: ceil(2.5 × peak BytesIn + 8), minimum 10 MiB/s. FSx: 384 MiB/s supports 150 MiB/s BytesIn; larger sizes scale linearly, at most 16 systems.')
        self.ui.confirm('CMP will create the file systems. Console Policy will include file-system creation, lifecycle, tagging and required network permissions. Confirm delegation.')

    def instance_type(self):
        catalog = json.loads((Path(__file__).parent / 'instance-catalog.json').read_text())
        available = None
        for subnet in self.state['subnets']:
            rows = self.aws.read('ec2', 'describe-instance-type-offerings', '--location-type', 'availability-zone', '--filters', f'Name=location,Values={subnet["AvailabilityZone"]}')['InstanceTypeOfferings']
            offered = {x['InstanceType'] for x in rows}
            available = offered if available is None else available & offered
        candidates = [x for x in catalog if x['type'] in available]
        if not candidates: raise SetupError('No catalog instance type is offered in every selected AZ.')
        chosen = self.ui.choose('Instance type available in every selected AZ', lambda: candidates,
            lambda x: f'{x["type"]} | {x["cpu"]} vCPU | {x["memoryGiB"]} GiB | {x["architecture"]}', lambda x: x['type'], refresh=False)
        self.state.update(instance_type=chosen['type'], instance_spec=chosen)
        if self.state['deploy_type'] == 'IAAS':
            arch = 'arm64' if chosen['architecture'] == 'arm' else 'x86_64'
            version = cluster_version(self.state['home'])
            images = self.aws.read('ec2', 'describe-images', '--filters', f'Name=name,Values=AutoMQ-automq-kafka-Prod-{version}-{arch}', 'Name=state,Values=available')['Images']
            if not images: raise SetupError(f'No accessible AutoMQ {version} AMI for this architecture.')

    def payment(self):
        self.state['payment'] = {'paymentType': self.option('EC2 purchase option', [('ON_DEMAND', 'On demand'), ('RESERVED', 'Reserved')])}

    def payment_term(self):
        months = int(self.option('Reserved term', [(str(n), f'{n} months') for n in [1,3,6,12,24,36]]))
        self.state['payment'].update(paymentPeriod=months if months <= 12 else months // 12, paymentPeriodUnit='MONTH' if months <= 12 else 'YEAR')

    def client_network(self):
        self.state['client_network'] = self.option('Application location', [('vpc', 'Selected VPC'), ('other', 'Other network')])
        if self.state['client_network'] == 'other': self.ui.show('Arrange network access and private DNS association/forwarding where applicable. DNS visibility alone does not provide network connectivity.')

    def transport(self):
        self.state['transport'] = self.multi('Kafka transport', ['plaintext', 'tls'], str, current='1')

    def authentication(self):
        self.state['auth'] = self.multi('Kafka authentication', ['sasl', 'anonymous', 'mtls'], str, current='1')
        self.state['listeners'] = listeners(self.state['transport'], self.state['auth'])
        for row in self.state['listeners']: self.ui.show(f'{row["protocol"]}: TCP {row["port"]}')

    def dns_mode(self):
        self.state['dns_mode'] = self.option('DNS mode', [('private', 'Private DNS'), ('public', 'Public DNS — platform managed')])

    def dns(self):
        if self.state['dns_mode'] == 'private': return super().dns()
        from home import prepare_public_dns
        self.ui.confirm('Home will create or reuse the environment public zone, DNS Role and optional TLS certificate. Confirm platform management and scoped AssumeRole permissions.')
        with operation(self.ui.show, 'Preparing public DNS through Home'):
            result = prepare_public_dns(self.state['home'], 'tls' in self.state['transport'])
        self.state['public_dns'] = result
        self.state['zone'] = {'Id': result['hostedZoneId'], 'Name': result.get('domainName', '')}

    def certificate(self):
        from certificates import certificate_info, preparation
        choice = self.option('TLS server certificate', [('file', 'Use existing certificate files'), ('command', 'Show preparation command')])
        if choice == 'command': self.ui.preparation(preparation(self.directory, self.state['zone']['Name']))
        path, pem = self.file('Certificate chain file path')
        certificate_info(pem, self.state['zone']['Name'])
        self.state['tls_material'] = {'certificateChain': pem}
        self.state['certificate_path'] = str(path)

    def private_key(self):
        from certificates import validate_key
        _, pem = self.file('Private key file path')
        validate_key(self.state['tls_material']['certificateChain'], pem)
        self.state['tls_material']['privateKey'] = pem

    def client_ca(self):
        from certificates import certificate_info
        _, pem = self.file('Client CA certificate file path')
        certificate_info(pem, ca=True)
        self.state.setdefault('tls_material', {})['certificateAuthority'] = pem

    def schema(self):
        self.state['schema'] = self.option('Schema Registry', [('off','Disabled'),('on','Enabled')]) == 'on'

    def metrics_mode(self):
        self.state['metrics_auth'] = self.option('Prometheus Remote Write', [('off','Disabled'),('sigv4','AMP / SigV4'),('basic','Basic authentication'),('bearer','Bearer token'),('noauth','No authentication')])

    def metrics_target(self):
        auth = self.state['metrics_auth']; result = {'enabled': True, 'authType': auth}
        if auth == 'sigv4':
            row = self.ui.choose('AMP Workspace', lambda: self.aws.read('amp','list-workspaces')['workspaces'], lambda x: f'{x.get("alias", "-")} | {x["workspaceId"]} | {x["arn"]}', lambda x: x['workspaceId'])
            ws = self.aws.read('amp','describe-workspace','--workspace-id',row['workspaceId'])['workspace']
            if ws['status']['statusCode'] != 'ACTIVE': raise SetupError('AMP Workspace must be ACTIVE.')
            result.update(prometheusArn=ws['arn'], endPoint=ws['prometheusEndpoint'].rstrip('/')+'/api/v1/remote_write')
        else:
            endpoint = self.ui.prompt('Remote Write URL')
            parsed = urlparse(endpoint)
            if parsed.scheme not in ['https','http'] or not parsed.hostname or parsed.username or parsed.password: raise SetupError('Enter an HTTP(S) URL without embedded credentials.')
            result['endPoint'] = endpoint
            if auth == 'basic': result.update(username=self.ui.prompt('Username'), password=self.secret('Password'))
            if auth == 'bearer': result['token'] = self.secret('Bearer token')
        result['labels'] = self.label_input('Optional metrics labels as JSON name/value list', allow_empty=True)
        self.state['metrics'] = result

    def label_input(self, title, allow_empty=True):
        raw = self.ui.prompt(title, '[]')
        try: rows = json.loads(raw)
        except ValueError: raise SetupError('Enter a JSON list of {"name":"...","value":"..."}.') from None
        if not isinstance(rows, list) or len(rows) > 20 or any(not isinstance(x,dict) or set(x) != {'name','value'} or not all(isinstance(v,str) and v for v in x.values()) for x in rows):
            raise SetupError('Use up to 20 name/value pairs with non-empty strings.')
        if len({x['name'] for x in rows}) != len(rows): raise SetupError('Names must be unique.')
        return rows

    def custom_tags(self):
        self.state['tags'] = self.label_input('Optional custom tags as JSON name/value list')
        if any(x['name'].startswith(('aws:', 'automq')) for x in self.state['tags']): raise SetupError('Do not replace reserved AWS or AutoMQ tags.')

    def data_bucket(self):
        from resources import bucket_command
        mode = self.option('Data Bucket', [('managed','CMP creates and manages'),('existing','Choose existing / show preparation command')])
        self.state['data_bucket'] = None
        if mode == 'managed': return super().data_bucket()
        row = self.ui.choose('Data Bucket', lambda: self.aws.read('s3api','list-buckets')['Buckets'], lambda x: f'{x["Name"]} | arn:aws:s3:::{x["Name"]}', lambda x: x['Name'], prepare=lambda:bucket_command(self.directory,self.state))
        name = row['Name']
        with operation(self.ui.show,'Checking Bucket Region and lifecycle'):
            region = self.aws.read('s3api','get-bucket-location','--bucket',name).get('LocationConstraint') or 'us-east-1'
            if region == 'EU': region = 'eu-west-1'
            if region != self.aws.region: raise SetupError('Bucket must be in the selected Region.')
            rules = self.aws.read('s3api','get-bucket-lifecycle-configuration','--bucket',name).get('Rules',[])
            if any(r.get('Status') == 'Enabled' and any(k in r for k in ['Expiration','NoncurrentVersionExpiration','AbortIncompleteMultipartUpload','Transitions','NoncurrentVersionTransitions']) for r in rules):
                raise SetupError('Bucket lifecycle may remove or transition AutoMQ data. Resolve the rules and refresh.')
        self.ui.show('Existing Bucket encryption is not checked. If using KMS, provide Key Policy and additional IAM access separately.')
        self.state['data_bucket'] = name

    def security_group(self, fs=False):
        from resources import sg_rules, sg_command, validate_sg
        rules = sg_rules(self.state,fs)
        for port,cidr,purpose in rules: self.ui.show(f'TCP {port} | {cidr} | {purpose}')
        mode = self.option('Security group preparation', [('managed','CMP creates and manages'),('existing','Choose existing / show preparation command')])
        if mode == 'managed':
            self.ui.confirm('CMP Policy will include tagged security-group creation, rule management and required network permissions. Confirm delegation.')
            return []
        def fetch():
            return self.aws.read('ec2','describe-security-groups','--filters',f'Name=vpc-id,Values={self.state["vpc"]["VpcId"]}')['SecurityGroups']
        groups=self.multi('Security groups',fetch(),lambda x:f'{x["GroupName"]} | {x["GroupId"]}',fetch=fetch,
            prepare=lambda:sg_command(self.directory,self.state,'fs-sg' if fs else 'cluster-sg',rules))
        if any(x['VpcId']!=self.state['vpc']['VpcId'] for x in groups): raise SetupError('Selected groups must belong to the selected VPC.')
        combined={'VpcId':self.state['vpc']['VpcId'],'IpPermissions':[r for g in groups for r in g.get('IpPermissions',[])],
                  'IpPermissionsEgress':[r for g in groups for r in g.get('IpPermissionsEgress',[])]}
        with operation(self.ui.show,'Checking selected security-group rules'):
            validate_sg(combined,self.state['vpc']['VpcId'],rules)
        self.ui.show(json.dumps(combined,indent=2))
        self.ui.confirm('Confirm these sources cover your clients/workloads and outbound access is suitable. Rule presence does not prove connectivity.')
        return groups

    def cluster_sg(self):
        self.state['cluster_security_groups'] = self.security_group()

    def fs_subnets(self):
        azs = [x['AvailabilityZone'] for x in self.state['subnets']]
        rows = self.subnets('EFS mount-target subnets',len(azs),azs)
        self.state['filesystem']['subnetIds'] = [x['SubnetId'] for x in rows]

    def fs_sg(self):
        groups = self.security_group(True)
        if groups: self.state['filesystem']['securityGroups'] = [x['GroupId'] for x in groups]

    def console_deployment(self):
        options = [('K8S','EKS (reuse AutoMQ EKS by default)'),('IAAS','EC2')] if self.state['deploy_type']=='K8S' else [('IAAS','EC2'),('K8S','EKS')]
        self.state['console_deploy'] = self.option('Install Console on',options)

    def console_subnet(self):
        rows = self.subnets('Console subnet',1)
        self.state['console_subnet'] = rows[0]

    def console_source(self):
        super().console_source()
        self.ui.show(f'Console subnet: {self.state["console_subnet"]["SubnetId"]}')

    def console_key(self):
        original = self.state['subnet']
        try:
            self.state['subnet'] = self.state['console_subnet']
            super().console_key()
        finally: self.state['subnet'] = original

    def console_password(self):
        password = self.secret('Initial Console admin password (at least 12 characters)')
        if len(password)<12: raise SetupError('Use at least 12 characters.')
        self.state['console_password'] = password
        if self.state['console_deploy']=='IAAS':
            self.state['console_config'] = {'security_group':self.state['console_security_group'],'key_name':self.state['console_key_pair']['KeyName'],'ami':self.state['console_ami'],'password':password}

    def service_access(self):
        from endpoints import inspect_endpoints,s3_command
        subnet_ids = [x['SubnetId'] for x in self.state['subnets']]
        subnet_ids += [x['SubnetId'] for x in self.state['console_eks_subnets']] if self.state.get('console_eks') else [self.state['console_subnet']['SubnetId']]
        while True:
            result = inspect_endpoints(self.aws,self.state['vpc']['VpcId'],subnet_ids,self.state)
            command = s3_command(self.directory,self.state,result)
            self.ui.section('S3 Gateway Endpoint — required')
            for subnet,table in result['subnetRouteTables'].items(): self.ui.show(f'{subnet} → {table}')
            if result['s3MissingRouteTables']:
                if command:
                    self.ui.show('Missing S3 Gateway route-table associations. New endpoints use the default policy; existing policies are preserved.')
                    self.ui.preparation(command, 'Back to dependency check')
                else:
                    self.ui.show(json.dumps(result['s3Unready']))
                    self.ui.prompt('Wait for endpoint availability, then enter r to refresh.')
                continue
            write_private(self.directory/'s3-endpoint-policy-review.json',[{'id':e['VpcEndpointId'],'policy':e.get('PolicyDocument')} for e in result['s3Gateways']])
            for row in result['interfaces']: self.ui.show(f'{row["service"]}: {row["endpoints"] or "no matching endpoint"}')
            self.ui.show('Review s3-endpoint-policy-review.json. Interface Endpoint records do not prove connectivity. Home/image repositories still require HTTPS access.')
            self.ui.confirm('Confirm endpoint policies permit Ops/Data operations and required AWS APIs are reachable from Console and nodes.')
            result['userConfirmed']=True
            self.state['service_access']=result
            return

    def choose_eks(self):
        from eks import validate_cluster
        name=self.ui.choose('Existing EKS cluster',lambda:self.aws.read('eks','list-clusters')['clusters'],str,str)
        cluster=self.aws.read('eks','describe-cluster','--name',name)['cluster']
        validate_cluster(cluster,self.state['vpc']['VpcId'])
        self.ui.show(f'{cluster["name"]} | {cluster["arn"]} | Kubernetes {cluster["version"]}')
        self.ui.confirm('Confirm this Kubernetes version is supported by your AutoMQ release, and Console can reach its API endpoint. AWS ACTIVE does not prove these conditions.')
        return cluster

    def eks_target(self):
        self.state['eks']=self.choose_eks()
        self.state.update(namespace='automq', service_account='automq-sa')

    def workload_namespace(self):
        value=self.text('namespace','AutoMQ Kubernetes namespace','automq')
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',value): raise SetupError('Use a Kubernetes DNS label of at most 63 characters.')

    def workload_serviceaccount(self):
        value=self.text('service_account','AutoMQ Kubernetes ServiceAccount','automq-sa')
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',value): raise SetupError('Use a Kubernetes DNS label of at most 63 characters.')

    def eks_capacity(self):
        from eks import nodegroup_command
        mode=self.option('EKS compute capacity',[('managed','Existing managed node group / prepare dedicated group'),('karpenter','Karpenter NodePool')])
        self.state['capacity_mode']=mode
        if mode=='managed':
            name=self.ui.choose('Managed node group',lambda:self.aws.read('eks','list-nodegroups','--cluster-name',self.state['eks']['name'])['nodegroups'],str,str,prepare=lambda:nodegroup_command(self.directory,self.state))
            group=self.aws.read('eks','describe-nodegroup','--cluster-name',self.state['eks']['name'],'--nodegroup-name',name)['nodegroup']
            types=group.get('instanceTypes',[])
            if group.get('launchTemplate'):
                lt=group['launchTemplate']
                versions=self.aws.read('ec2','describe-launch-template-versions','--launch-template-id',lt['id'],'--versions',lt.get('version','$Default'))['LaunchTemplateVersions']
                types += [v['LaunchTemplateData']['InstanceType'] for v in versions if v.get('LaunchTemplateData',{}).get('InstanceType')]
            if group['status']!='ACTIVE' or self.state['instance_type'] not in types: raise SetupError('Node group must be ACTIVE and support the chosen instance type.')
            needed={x['SubnetId'] for x in self.state['subnets']}
            if not needed <= set(group['subnets']): raise SetupError('Node group does not cover the selected compute subnets.')
            if group['scalingConfig']['maxSize']<self.state['node_count']: raise SetupError('Node group maximum is smaller than the requested AutoMQ node count.')
            self.state['nodegroup']=group
            self.ui.show(json.dumps({'scaling':group['scalingConfig'],'labels':group.get('labels',{}),'taints':group.get('taints',[])},indent=2))
        self.ui.confirm('Confirm dedicated compute capacity, CPU/memory headroom, AZ placement and scaling are suitable. Declared node counts do not prove available capacity; Karpenter provisioning must match the selected machine and subnets.')

    def eks_schedule(self):
        from eks import scheduling
        mode=self.option('Scheduling',[('default','Use selected managed node group / default scheduling'),('file','Read scheduling YAML/JSON file')])
        if mode=='file':
            _,raw=self.file('Scheduling file path')
            self.state['schedule']=scheduling(raw)
        elif self.state.get('nodegroup'):
            group=self.state['nodegroup']
            tolerations=[{'key':x['key'],'value':x.get('value',''),'operator':'Equal','effect':{'NO_SCHEDULE':'NoSchedule','NO_EXECUTE':'NoExecute','PREFER_NO_SCHEDULE':'PreferNoSchedule'}[x['effect']]} for x in group.get('taints',[])]
            self.state['schedule']=scheduling(json.dumps({'affinity':{'nodeAffinity':{'requiredDuringSchedulingIgnoredDuringExecution':{'nodeSelectorTerms':[{'matchExpressions':[{'key':'eks.amazonaws.com/nodegroup','operator':'In','values':[group['nodegroupName']]}]}]}}},'tolerations':tolerations}))
        else:
            raise SetupError('Karpenter/self-managed capacity requires an explicit scheduling file matching your node pool.')

    def lb_subnets(self):
        mode=self.option('Kafka NLB subnets',[('reuse','Reuse compute subnets'),('select','Select other existing subnets')])
        self.state['lb_subnets']=self.state['subnets'] if mode=='reuse' else self.subnets('NLB subnets',self.state['az_count'],[x['AvailabilityZone'] for x in self.state['subnets']])
        for x in self.state['lb_subnets']:
            if x['AvailableIpAddressCount']<8: raise SetupError('NLB subnets need at least 8 free IP addresses.')

    def collect_evidence(self,cluster,purpose,console=False):
        from eks import evidence_command,check_evidence
        path=evidence_command(self.directory,self.state,cluster,purpose)
        self.ui.preparation(path, 'Back to evidence input')
        self.ui.show('Run the collection file where Kubernetes API access is available; copy the JSON result here.')
        _,raw=self.file('Collected evidence JSON path')
        try: data=json.loads(raw)
        except ValueError: raise SetupError('Invalid evidence JSON.') from None
        self.state[purpose+'_evidence']=data
        if not console and self.state.get('capacity_mode')=='karpenter':
            from eks import validate_karpenter
            pools=data.get('nodepools',{}).get('items',[])
            pool=self.ui.choose('Karpenter NodePool from evidence',lambda:pools,lambda x:x['metadata']['name'],lambda x:x['metadata']['name'],refresh=False)
            validate_karpenter(pool,data,self.state)
        from eks import component_commands
        preparation=component_commands(self.directory,self.state,cluster,data,purpose,console)
        try:
            with operation(self.ui.show,'Checking EKS component evidence'):
                result=check_evidence(data,cluster,self.state['wal'],console)
        except SetupError:
            self.ui.show('Missing components can be prepared with the following file. Existing conflicting or unhealthy components must be repaired separately.')
            self.ui.preparation(preparation, 'Back to EKS checks')
            raise
        self.ui.show(f'Optional preparation for missing components: {preparation}')
        self.ui.show(json.dumps(result,indent=2))
        self.ui.show('Required access: Console → EKS API TCP 443; Console → Pod metrics TCP 9090 and internal broker TCP 9102; applications → selected Kafka listener ports. NLB targets require Pod IPs routable in the VPC.')
        self.ui.confirm('Confirm evidence is current, Pod IPs use VPC subnets, CNI configuration/ENIConfig and network access are appropriate, CSI IAM is configured, and workload capacity is sufficient.')
        return result

    def eks_prerequisites(self):
        self.state['eks_checks']=self.collect_evidence(self.state['eks'],'automq-eks')

    def console_eks(self):
        if self.state.get('eks') and self.option('Console EKS',[('reuse','Reuse AutoMQ EKS'),('select','Select another existing EKS')])=='reuse':
            cluster=self.state['eks']
        else: cluster=self.choose_eks()
        self.state['console_eks']=cluster
        self.state['console_eks_checks']=self.collect_evidence(cluster,'console-eks',True)

    def console_eks_subnets(self):
        self.ui.show('Select the subnets used by the system nodes that will host Console, not only the EKS control-plane subnets.')
        self.state['console_eks_subnets']=self.subnets('Console EKS workload subnets')
        self.ui.confirm('Confirm untainted system-node capacity exists in these subnets for Console (2 vCPU, 8 GiB available). Console will be restricted to their AZs.')

    def binding(self,purpose):
        cluster=self.state['eks' if purpose=='cluster' else 'console_eks']
        method=self.option('AWS workload identity',[('pod','EKS Pod Identity'),('irsa','IRSA')])
        if method=='pod':
            addons=self.aws.read('eks','list-addons','--cluster-name',cluster['name'])['addons']
            data=self.state.get(('automq-eks' if purpose=='cluster' else 'console-eks')+'_evidence',{})
            agent=next((x for x in data.get('daemonsets',{}).get('items',[]) if x['metadata']['name']=='eks-pod-identity-agent'),{})
            agent_ready=agent.get('status',{}).get('numberReady',0)>0 and agent.get('status',{}).get('numberReady')==agent.get('status',{}).get('desiredNumberScheduled')
            if 'eks-pod-identity-agent' not in addons and agent_ready:
                self.state[purpose+'_binding']=method
                return
            if 'eks-pod-identity-agent' not in addons:
                from resources import script
                path=script(self.directory,f'prepare-{purpose}-pod-agent.sh',[aws_command(self.aws.region,'eks','create-addon','--cluster-name',cluster['name'],'--addon-name','eks-pod-identity-agent')])
                self.ui.preparation(path,'Back to identity selection')
                raise SetupError('Install the Pod Identity Agent, then retry. Self-managed Agent installations require IRSA or managed-addon registration for this check.')
            addon=self.aws.read('eks','describe-addon','--cluster-name',cluster['name'],'--addon-name','eks-pod-identity-agent')['addon']
            if addon['status']!='ACTIVE': raise SetupError('Pod Identity Agent must be ACTIVE.')
        else:
            issuer=cluster['identity']['oidc']['issuer'].removeprefix('https://')
            try:
                self.aws.read('iam','get-open-id-connect-provider','--open-id-connect-provider-arn',f'arn:aws:iam::{self.state["account"]}:oidc-provider/{issuer}')
            except SetupError as error:
                if '(NoSuchEntity)' not in str(error): raise
                from resources import script
                command=shlex.join(['eksctl','utils','associate-iam-oidc-provider','--cluster',cluster['name'],'--region',self.aws.region,'--approve'])
                self.ui.preparation(script(self.directory,f'prepare-{purpose}-oidc.sh',[command]),'Back to identity selection')
                raise SetupError('Prepare the OIDC provider, then retry.') from None
        self.state[purpose+'_binding']=method

    def cluster_binding(self): self.binding('cluster')
    def console_binding(self): self.binding('console')

    def identity(self,key,purpose):
        is_cluster=key=='cluster_role'
        eks_identity=self.state.get('deploy_type')=='K8S' if is_cluster else self.state.get('console_mode')=='new' and self.state.get('console_deploy')=='K8S'
        if not eks_identity: return super().identity(key,purpose)
        from eks import trust,role_preparation,binding_commands
        cluster=self.state['eks' if is_cluster else 'console_eks']
        ns=self.state['namespace'] if is_cluster else 'automq-console'
        sa=self.state['service_account'] if is_cluster else 'automq-console'
        method=self.state['cluster_binding' if is_cluster else 'console_binding']
        expected=trust(self.state,cluster,ns,sa,method)
        role=self.ui.choose('IAM Role',lambda:self.aws.read('iam','list-roles')['Roles'],lambda x:f'{x["RoleName"]} | {x["Arn"]}',lambda x:x['RoleName'],prepare=lambda:role_preparation(self.directory,self.state,purpose,expected))
        role=self.aws.read('iam','get-role','--role-name',role['RoleName'])['Role']
        self.ui.section('Required trust policy')
        self.ui.show(json.dumps(expected,indent=2))
        self.ui.show('Selected Role trust:')
        self.ui.show(json.dumps(role['AssumeRolePolicyDocument'],indent=2))
        self.ui.confirm('Confirm the selected Role trust permits this EKS workload identity with the displayed scope. This is a user review, not an effective-permission check.')
        existing=None
        if method=='pod':
            rows=self.aws.read('eks','list-pod-identity-associations','--cluster-name',cluster['name'],'--namespace',ns,'--service-account',sa)['associations']
            if rows:
                existing=self.aws.read('eks','describe-pod-identity-association','--cluster-name',cluster['name'],'--association-id',rows[0]['associationId'])['association']
                if existing['roleArn']!=role['Arn']: raise SetupError('Existing Pod Identity association uses a different Role. Resolve it without overwriting blindly.')
        path=binding_commands(self.directory,self.state,cluster,ns,sa,method,role,purpose,existing)
        self.ui.preparation(path,'Back to Role review')
        self.ui.confirm('Confirm the namespace/ServiceAccount and identity binding have been prepared on the target EKS.')
        self.state[key]=role

    def eks_access(self):
        from resources import script
        cluster=self.state['eks']; role=self.state['console_role']['Arn']; region=self.aws.region
        entries=self.aws.read('eks','list-access-entries','--cluster-name',cluster['name'])['accessEntries']
        lines=[]
        if role not in entries:
            lines.append(aws_command(region,'eks','create-access-entry','--cluster-name',cluster['name'],'--principal-arn',role,'--type','STANDARD'))
        else:
            entry=self.aws.read('eks','describe-access-entry','--cluster-name',cluster['name'],'--principal-arn',role)['accessEntry']
            if entry['type']!='STANDARD': raise SetupError('Console access entry must have type STANDARD.')
        policies=[] if role not in entries else self.aws.read('eks','list-associated-access-policies','--cluster-name',cluster['name'],'--principal-arn',role)['associatedAccessPolicies']
        arn='arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy'
        if not any(p['policyArn']==arn and p['accessScope']['type']=='cluster' for p in policies):
            lines.append(aws_command(region,'eks','associate-access-policy','--cluster-name',cluster['name'],'--principal-arn',role,'--policy-arn',arn,'--access-scope','type=cluster'))
        if lines:
            self.ui.preparation(script(self.directory,'authorize-console-eks.sh',lines),'Back to EKS access check')
            raise SetupError('Run the EKS authorization commands, then retry this check.')
        self.ui.show('PASS: Console Role has STANDARD access entry and cluster-scoped AmazonEKSClusterAdminPolicy.')

    def review(self):
        from core import export,new_api_credentials,request_body
        from console import generate_console
        from eks_console import generate_eks_console
        body=request_body(self.state)
        safe=json.loads(json.dumps(body))
        security=safe['features']['security']
        for key in ['certificateChain','privateKey','certificateAuthority']:
            if key in security: security[key]='provided (hidden)'
        prometheus=safe['features'].get('metricsExporter',{}).get('prometheus',{})
        for key in ['password','token']:
            if key in prometheus: prometheus[key]='provided (hidden)'
        for item in safe['features'].get('instanceConfigs', []):
            item['value'] = 'provided (hidden)'
        self.ui.show(json.dumps(safe,indent=2))
        self.ui.confirm('Confirm configuration and reviewed policies. Creating the cluster is a later user-executed operation.')
        if self.state['console_mode']=='new':
            self.state['api_credentials']=new_api_credentials()
            if self.state['console_deploy']=='K8S': generate_eks_console(self.directory,self.state)
            else:
                snapshot=dict(self.state);snapshot['subnet']=self.state['console_subnet']
                generate_console(self.directory,snapshot)
        files=export(self.directory,self.state)
        self.ui.show(f'Generated files: {self.directory}')
        for path in files: self.ui.show(f'Authorization: bash {shlex.quote(str(path))}')
        if self.state['console_mode'] == 'new':
            if self.state['console_deploy'] == 'K8S':
                self.ui.show('Console installation: CONSOLE-INSTALL.md')
            else:
                self.ui.show('Console EC2 launch: bash prepare-console-ec2.sh. See CONSOLE-INSTALL.txt for the host installation.')
        self.ui.show('Sign the reviewed cluster request with generate-curl.sh. Run the generated curl where Console is reachable after installation, initialization and billing checks.')
