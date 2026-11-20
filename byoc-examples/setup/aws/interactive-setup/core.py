"""Read-only AWS discovery, scoped policy composition and deterministic output."""
from __future__ import annotations
import base64
import copy
import json
import ipaddress
import os
from pathlib import Path
import re
import shlex
import secrets
import string
import subprocess

TEMPLATES = Path(__file__).resolve().parent / 'templates'

class SetupError(Exception):
    pass

class Back(Exception):
    pass


def parse_home(command):
    # The Home command is data, never a shell program. Ignore its host-dir/password hints.
    config = re.findall(r'(?:^|\s)-e\s+[\"\']?CONFIG=([A-Za-z0-9+/=]+)[\"\']?(?=\s|$)', command)
    image = re.search(r'(automq\.azurecr\.io/automq/automq-byoc-console:[A-Za-z0-9_.-]+)\s*$', command)
    if len(config) != 1 or not image or not re.search(r'-e\s+CLOUD_PROVIDER=aws(?:\s|$)', command):
        raise SetupError('Docker command is incomplete or unsupported. Expected exactly one CONFIG, CLOUD_PROVIDER=aws, and the AutoMQ Console image at the end. Copy the entire command from Home, including its final image line.')
    try:
        decoded = json.loads(base64.b64decode(config[0], validate=True))
        required = ['environmentId', 'clientId', 'clientSecret', 'region', 'opsBucket']
        if not isinstance(decoded, dict) or any(not decoded.get(k) for k in required):
            raise ValueError()
        bucket = decoded['opsBucket']['bucketName']
        if not re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', bucket):
            raise ValueError()
        if not re.fullmatch(r'(?:af|ap|ca|eu|il|me|mx|sa|us)-[a-z]+-\d+', decoded['region']):
            raise ValueError()
        if not all(isinstance(decoded[k], str) for k in required[:-1]):
            raise ValueError()
    except (ValueError, KeyError, TypeError):
        raise SetupError('CONFIG is invalid or missing required AWS environment fields.') from None
    return {'config': config[0], 'image': image[1], **decoded}


class AWS:
    ALLOWED = {
        'sts': {'get-caller-identity'},
        'ec2': {'describe-vpcs', 'describe-vpc-attribute', 'describe-subnets',
                'describe-route-tables', 'describe-vpc-endpoints', 'describe-availability-zones',
                'describe-security-groups', 'describe-images',
                'describe-instance-types', 'describe-launch-template-versions', 'describe-instance-type-offerings', 'describe-instances', 'describe-key-pairs'},
        'iam': {'list-roles', 'get-role', 'list-instance-profiles-for-role',
                'list-attached-role-policies', 'get-open-id-connect-provider'},
        'route53': {'list-hosted-zones-by-vpc', 'get-hosted-zone', 'list-tags-for-resource'},
        'ssm': {'get-parameter'},
        's3api': {'list-buckets', 'get-bucket-location', 'get-bucket-lifecycle-configuration', 'get-bucket-tagging'},
        'eks': {'list-clusters', 'describe-cluster', 'list-nodegroups', 'describe-nodegroup', 'list-addons', 'describe-addon', 'list-pod-identity-associations', 'describe-pod-identity-association', 'list-access-entries', 'describe-access-entry', 'list-associated-access-policies'},
        'amp': {'list-workspaces', 'describe-workspace'},
    }
    def __init__(self, region, runner=subprocess.run):
        self.region, self.runner = region, runner

    def read(self, service, operation, *args):
        if operation not in self.ALLOWED.get(service, set()):
            raise SetupError('Cloud mutation is not supported by this guide.')
        # AWS CLI aggregates all service pages by default. UI paging is separate.
        cmd = ['aws', service, operation, '--region', self.region, '--output', 'json',
               '--no-cli-pager', '--cli-connect-timeout', '10', '--cli-read-timeout', '30', *args]
        try:
            result = self.runner(cmd, capture_output=True, text=True, timeout=120,
                                 env={**os.environ, 'AWS_PAGER': '', 'AWS_CLI_AUTO_PROMPT': 'off'})
        except (OSError, subprocess.TimeoutExpired):
            raise SetupError(f'{service}:{operation} could not complete. Check AWS CLI and retry.') from None
        if result.returncode:
            if operation == 'get-bucket-lifecycle-configuration' and '(NoSuchLifecycleConfiguration)' in result.stderr:
                return {'Rules': []}
            if operation == 'get-bucket-tagging' and '(NoSuchTagSet)' in result.stderr:
                return {'TagSet': []}
            code = re.search(r'\(([^)]+)\) when calling', result.stderr or '')
            raise SetupError(f'{service}:{operation} failed ({code[1] if code else "AWS CLI error"}). Retry after checking credentials and read permissions.')
        try:
            return json.loads(result.stdout)
        except ValueError:
            raise SetupError(f'{service}:{operation} returned invalid JSON.') from None


def name_of(resource):
    return next((t['Value'] for t in resource.get('Tags', []) if t['Key'] == 'Name'), '-')


def validate_network(aws, vpc, subnet, min_ips=4):
    if vpc.get('State') != 'available' or subnet.get('State') != 'available':
        raise SetupError('The selected VPC and subnet must be available.')
    if subnet['VpcId'] != vpc['VpcId']:
        raise SetupError('The selected subnet is not in the selected VPC.')
    for attr, field in [('enableDnsSupport', 'EnableDnsSupport'), ('enableDnsHostnames', 'EnableDnsHostnames')]:
        value = aws.read('ec2', 'describe-vpc-attribute', '--vpc-id', vpc['VpcId'], '--attribute', attr)
        if not value[field]['Value']:
            raise SetupError(f'VPC {attr} must be enabled. Correct it and select again.')
    if subnet['AvailableIpAddressCount'] < min_ips:
        raise SetupError(f'This subnet requires at least {min_ips} free IP addresses for the selected resources.')
    return {'dns': 'passed', 'freeIPs': subnet['AvailableIpAddressCount'],
            'connectivity': 'not checked; requirements require user confirmation'}


def validate_console_sg(group, vpc_id, source):
    if group['VpcId'] != vpc_id:
        raise SetupError('Console security group must belong to the selected VPC.')
    requested = ipaddress.ip_network(source)
    def permits(rules, port, cidr):
        for rule in rules:
            protocol = rule['IpProtocol']
            if protocol not in ('-1', 'tcp', '6'):
                continue
            if protocol != '-1' and not rule.get('FromPort', 65536) <= port <= rule.get('ToPort', -1):
                continue
            for value in rule.get('IpRanges', []):
                if cidr.subnet_of(ipaddress.ip_network(value['CidrIp'])):
                    return True
        return False
    for port in (22, 8080):
        if not permits(group['IpPermissions'], port, requested):
            raise SetupError(f'Console SG does not allow TCP {port} from {source}. The guide requires explicit CIDR rules; select or prepare another SG.')
    return {'ingress': 'selected source covers TCP 22 and 8080', 'egress': 'requirements require user confirmation', 'connectivity': 'not verified'}


def validate_role(aws, role, show=None):
    profiles = aws.read('iam', 'list-instance-profiles-for-role', '--role-name', role['RoleName'])['InstanceProfiles']
    if not profiles:
        name = role['RoleName']
        create = aws_command(aws.region, 'iam', 'create-instance-profile', '--instance-profile-name', name)
        attach = aws_command(aws.region, 'iam', 'add-role-to-instance-profile', '--instance-profile-name', name, '--role-name', name)
        raise SetupError(f'Role {name} has no Instance Profile. EC2 needs a Profile containing this Role.\n'
                         'If the Profile name below is unused, run these commands in order; only run the second after creation succeeds. '
                         'If the name is already used, inspect that Profile or use a new name in both commands.\n'
                         f'{create}\n{attach}\n'
                         'Then refresh and select the Role again. IAM changes may take time to become visible.')
    if show and len(profiles) > 1:
        show(f'Found {len(profiles)} Instance Profiles. CMP uses the first returned Profile for this Role; '
             f'current first: {profiles[0]["Arn"]}. The new Console installation uses this exact ARN.')
    trust = role.get('AssumeRolePolicyDocument', {})
    statements = trust.get('Statement', [])
    if isinstance(statements, dict):
        statements = [statements]
    def allows(s):
        principal = s.get('Principal', {})
        services = principal.get('Service', []) if isinstance(principal, dict) else []
        actions = s.get('Action', [])
        return (s.get('Effect') == 'Allow' and
                'ec2.amazonaws.com' in ([services] if isinstance(services, str) else services) and
                'sts:AssumeRole' in ([actions] if isinstance(actions, str) else actions))
    if not any(allows(s) for s in statements):
        raise SetupError('The Role trust policy does not explicitly allow EC2 AssumeRole.')
    # Conditions, explicit deny, SCP, boundaries remain manual review, not an effective-permission test.
    return profiles[0]


def write_private(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, 'w') as f:
        os.fchmod(f.fileno(), 0o600)
        f.write(value if isinstance(value, str) else json.dumps(value, indent=2) + '\n')


def render(value, bindings):
    if isinstance(value, str):
        if value in bindings:
            return bindings[value]
        for key, replacement in bindings.items():
            if isinstance(replacement, str):
                value = value.replace(key, replacement)
        if re.search(r'<[^>]+>', value):
            raise SetupError(f'Unresolved policy parameter: {value}')
        return value
    if isinstance(value, list):
        result = []
        for v in value:
            r = render(v, bindings)
            result.extend(r if isinstance(r, list) else [r])
        return result
    if isinstance(value, dict):
        return {k: render(v, bindings) for k, v in value.items()}
    return value


def combine(modules, selected, bindings):
    result = {'Version': '2012-10-17', 'Statement': []}
    for key in selected:
        result['Statement'].extend(render(copy.deepcopy(modules[key]['Statement']), bindings))
    sids = [s['Sid'] for s in result['Statement']]
    if len(sids) != len(set(sids)) or any(not s['Resource'] for s in result['Statement']):
        raise SetupError('Policy has duplicate statements or an empty resource scope.')
    return result


def split_policy(policy, limit=6144):
    parts, current = [], {'Version': '2012-10-17', 'Statement': []}
    for statement in policy['Statement']:
        candidate = {**current, 'Statement': current['Statement'] + [statement]}
        if len(json.dumps(candidate, separators=(',', ':'))) > limit:
            if not current['Statement']:
                raise SetupError('One IAM statement exceeds the managed policy size limit.')
            parts.append(current)
            current = {'Version': '2012-10-17', 'Statement': [statement]}
            if len(json.dumps(current, separators=(',', ':'))) > limit:
                raise SetupError('One IAM statement exceeds the managed policy size limit.')
        else:
            current = candidate
    if current['Statement']:
        parts.append(current)
    return parts


def policies(state):
    account, region = state['account'], state['home']['region']
    prefix = f'arn:aws:ec2:{region}:{account}:'
    bindings = {
        '<account-id>': account, '<region>': region,
        '<ops-bucket>': state['home']['opsBucket']['bucketName'],
        '<data-bucket>': state.get('data_bucket') or 'automq-data-*', '<zone-id>': state['zone']['Id'].split('/')[-1],
        '<private-zone-id>': state['zone']['Id'].split('/')[-1],
        '<vpc-arn>': prefix + 'vpc/' + state['vpc']['VpcId'],
        '<compute-subnet-arn>': [prefix + 'subnet/' + x['SubnetId'] for x in state.get('subnets', [state['subnet']])],
        '<user-security-group-arn>': [prefix + 'security-group/' + x['GroupId'] for x in state.get('cluster_security_groups', [])],
        '<cluster-role-arn>': state['cluster_role']['Arn'],
        '<managed-ec2-resource-arn>': [prefix + k + '/*' for k in ['instance', 'volume', 'key-pair', 'launch-template', 'security-group']],
        '<attached-policy-arn>': state.get('attached_policies', []),
    }
    if state.get('eks'):
        bindings.update({'<eks-cluster-arn>': state['eks']['arn'], '<eks-name>': state['eks']['name']})
    if state.get('public_dns'):
        bindings.update({'<home-dns-role-arn>': state['public_dns']['crossAccountRole'], '<tls-assume-role-arn>': state['public_dns']['crossAccountRole']})
    if state.get('metrics', {}).get('prometheusArn'):
        bindings['<amp-workspace-arn>'] = state['metrics']['prometheusArn']
    cluster_modules = json.loads((TEMPLATES / 'cluster-policy-modules.json').read_text())
    cluster_keys = ['base', 'eks-volumes' if state.get('deploy_type') == 'K8S' else 'ec2-volumes']
    public_dns = state.get('dns_mode') == 'public'
    if public_dns:
        cluster_keys.append('TlsAssumeRole')
    # CMP requires these actions on the cluster role when validating TLS.
    if not public_dns or 'tls' in state.get('transport', []):
        cluster_keys.append('TlsDns')
    if state.get('metrics', {}).get('prometheusArn'): cluster_keys.append('amp')
    cluster = combine(cluster_modules, cluster_keys, bindings)
    for statement in cluster['Statement']:
        if not state.get('data_bucket') and statement['Sid'] in ['DataBucketList', 'DataObjects']:
            statement['Condition'] = {'StringEquals': {'s3:ResourceAccount': account}}
    policy_prefix = f'arn:aws:iam::{account}:policy/automq-setup-{state["name"]}'
    generated = [f'{policy_prefix}-cluster-role-{i}'
                 for i in range(1, len(split_policy(cluster)) + 1)]
    # CMP reads every managed policy attached to Console Role during browser initialization.
    generated.append(f'{policy_prefix}-console-role-*')
    bindings['<attached-policy-arn>'] = sorted(set(bindings['<attached-policy-arn>'] + generated))
    console_modules = json.loads((TEMPLATES / 'console-policy-modules.json').read_text())
    console_keys = ['base', 'ops-cross-account', 'discovery',
                    'data-existing' if state.get('data_bucket') else 'data-managed',
                    'dns-public' if state.get('dns_mode') == 'public' else 'dns-private', 'pricing']
    if state.get('deploy_type') == 'K8S':
        console_keys.append('eks')
    else:
        console_keys += ['ec2', 'asg', 'ec2-tags']
    if (state.get('deploy_type') != 'K8S' and not state.get('cluster_security_groups') or
            state.get('filesystem') and not state['filesystem'].get('securityGroups')):
        console_keys.append('managed-sg')
    if state.get('filesystem'):
        console_keys.append('efs' if state['filesystem']['fileSystemType'] == 'EFS_PROVISIONED' else 'fsx')
    if state.get('deploy_type') == 'K8S' and 'managed-sg' in console_keys:
        sg_tags = copy.deepcopy(console_modules['ec2-tags'])
        sg_tags['Statement'] = [x for x in sg_tags['Statement'] if x['Sid'] != 'TagNetworkInterfaceDuringRun']
        for statement in sg_tags['Statement']:
            statement['Resource'] = [prefix + 'security-group/*']
            if statement['Sid'] == 'TagEC2DuringCreate':
                statement['Condition']['StringEquals']['ec2:CreateAction'] = 'CreateSecurityGroup'
        console_modules['eks-sg-tags'] = sg_tags
        console_keys.append('eks-sg-tags')
    console = combine(console_modules, console_keys, bindings)
    return cluster, console


def request_body(state):
    from model import request
    return request(state)


def aws_command(region, service, op, *args):
    return shlex.join(['aws', service, op, '--region', region, '--no-cli-pager', *args])


def tags(deployment, purpose):
    return [{'Key': k, 'Value': v} for k, v in {
        'automq-product': 'automq', 'automq-origin': 'setup-command',
        'automq-deployment': deployment, 'automq-purpose': purpose}.items()]


def role_commands(directory, region, deployment, purpose):
    name = f'automq-setup-{deployment}-{purpose}'
    trust = {'Version': '2012-10-17', 'Statement': [{'Effect': 'Allow', 'Principal': {'Service': 'ec2.amazonaws.com'}, 'Action': 'sts:AssumeRole'}]}
    write_private(directory / f'{purpose}-trust.json', trust)
    write_private(directory / f'{purpose}-tags.json', tags(deployment, purpose))
    lines = ['#!/usr/bin/env bash', 'set -euo pipefail', 'cd -- "$(dirname -- "$0")"',
             aws_command(region, 'iam', 'create-role', '--role-name', name, '--assume-role-policy-document', f'file://{purpose}-trust.json', '--tags', f'file://{purpose}-tags.json'),
             aws_command(region, 'iam', 'wait', 'role-exists', '--role-name', name),
             aws_command(region, 'iam', 'create-instance-profile', '--instance-profile-name', name, '--tags', f'file://{purpose}-tags.json'),
             aws_command(region, 'iam', 'add-role-to-instance-profile', '--instance-profile-name', name, '--role-name', name)]
    path = directory / f'prepare-{purpose}.sh'
    write_private(path, '\n'.join(lines) + '\n')
    return path


def zone_commands(directory, state):
    name = f'{state["name"]}.automq.internal'
    cmd = aws_command(state['home']['region'], 'route53', 'create-hosted-zone', '--name', name,
                      '--vpc', f'VPCRegion={state["home"]["region"]},VPCId={state["vpc"]["VpcId"]}',
                      '--caller-reference', state['name'], '--hosted-zone-config', 'PrivateZone=true')
    tag_args = [f'Key={t["Key"]},Value={t["Value"]}' for t in tags(state['name'], 'private-dns')]
    path = directory / 'prepare-private-zone.sh'
    write_private(path, '#!/usr/bin/env bash\nset -euo pipefail\nSETUP_ZONE_ID=$(' + cmd + " --query HostedZone.Id --output text)\n" +
                  aws_command(state['home']['region'], 'route53', 'change-tags-for-resource', '--resource-type', 'hostedzone') +
                  ' --resource-id "${SETUP_ZONE_ID##*/}" --add-tags ' + shlex.join(tag_args) + '\nprintf "%s\\n" "$SETUP_ZONE_ID"\n')
    return path


def new_api_credentials():
    alphabet = string.ascii_letters + string.digits
    return {'accessKey': ''.join(secrets.choice(alphabet) for _ in range(16)),
            'secretKey': ''.join(secrets.choice(alphabet) for _ in range(32))}


def create_command(directory, state):
    credentials = state.get('api_credentials') or {'accessKey': 'REPLACE_CMP_ACCESS_KEY', 'secretKey': 'REPLACE_CMP_SECRET_KEY'}
    write_private(directory / 'cmp-credentials.json', credentials)
    signer = (Path(__file__).parent / 'cmp_sign.py').read_text()
    write_private(directory / 'cmp-sign.py', signer)
    write_private(directory / 'cmp_sign.py', signer)
    write_private(directory / 'cleanup.py', (Path(__file__).parent / 'cleanup.py').read_text())
    write_private(directory / 'cleanup.sh', '#!/usr/bin/env bash\nset -euo pipefail\numask 077\ncd -- "$(dirname -- "$0")"\nexec python3 cleanup.py "$@"\n')
    write_private(directory / 'generate-curl.sh', '#!/usr/bin/env bash\nset -euo pipefail\numask 077\ncd -- "$(dirname -- "$0")"\n[ "$#" -eq 2 ] || { echo \'Usage: bash generate-curl.sh CONSOLE_URL NEW_OUTPUT_DIRECTORY\'; exit 1; }\n# Offline generation only. The URL must be reachable from the eventual execution machine.\npython3 cmp-sign.py "$1" --request cluster-request.json --credentials cmp-credentials.json --output "$2"\n')


def export(directory, state):
    cluster, console = policies(state)
    write_private(directory / 'cluster-request.json', request_body(state))
    write_private(directory / 'review.json', {
        'name': state['name'], 'environmentId': state['home']['environmentId'], 'account': state['account'],
        'region': state['home']['region'], 'vpc': state['vpc']['VpcId'], 'subnet': state['subnet']['SubnetId'],
        'deployType': state.get('deploy_type', 'IAAS'), 'wal': state.get('wal', 'EBSWAL'),
        'nodeCount': state.get('node_count', 3), 'filesystem': state.get('filesystem'),
        'listeners': state.get('listeners'), 'eks': state.get('eks', {}).get('name'),
        'peakBytesInMiBps': state['peak'], 'dnsZone': state['zone']['Id'],
        'clusterRole': state['cluster_role']['Arn'], 'consoleRole': state['console_role']['Arn'],
        'consoleMode': state.get('console_mode'), 'consoleDeploy': state.get('console_deploy'),
        'consoleEksArn': state.get('console_eks', {}).get('arn'),
        'network': state['network'], 'vpcServiceAccess': state.get('service_access'), 'policyReview': 'user-confirmed',
        'cloudDeployment': 'not executed', 'submission': 'offline signing reads the credential file; user transfers the signed curl bundle and executes it in the Console network',
    })
    scripts = []
    for purpose, policy in [('cluster-role', cluster), ('console-role', console)]:
        write_private(directory / f'{purpose}-policy.json', policy)
        commands = ['#!/usr/bin/env bash', 'set -euo pipefail', 'cd -- "$(dirname -- "$0")"']
        role = state['cluster_role' if purpose == 'cluster-role' else 'console_role']['RoleName']
        for index, part in enumerate(split_policy(policy), 1):
            file = f'{purpose}-policy-{index}.json'
            write_private(directory / file, part)
            # Per-run names avoid overwriting or detaching historical policies.
            pname = f'automq-setup-{state["name"]}-{purpose}-{index}'
            commands += ['SETUP_POLICY_ARN=$(' + aws_command(state['home']['region'], 'iam', 'create-policy',
                '--policy-name', pname, '--policy-document', f'file://{file}', '--tags', json.dumps(tags(state['name'], purpose)),
                '--query', 'Policy.Arn', '--output', 'text') + ')',
                aws_command(state['home']['region'], 'iam', 'attach-role-policy', '--role-name', role) + ' --policy-arn "$SETUP_POLICY_ARN"']
        path = directory / f'authorize-{purpose}.sh'
        write_private(path, '\n'.join(commands) + '\n')
        scripts.append(path)
    create_command(directory, state)
    return scripts
