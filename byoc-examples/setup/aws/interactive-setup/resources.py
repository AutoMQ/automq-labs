"""Resource preparation commands; no automatic cloud mutations."""
import ipaddress
import json
import shlex
from core import aws_command, tags, write_private, SetupError


def script(directory, name, lines):
    path = directory / name
    write_private(path, '#!/usr/bin/env bash\nset -euo pipefail\numask 077\ncd -- "$(dirname -- "$0")"\n' + '\n'.join(lines) + '\n')
    return path


def bucket_command(directory, state):
    region = state['home']['region']
    name = f'automq-setup-{state["name"]}-{state["account"]}-{region}'
    args = ['--bucket', name]
    if region != 'us-east-1': args += ['--create-bucket-configuration', f'LocationConstraint={region}']
    return script(directory, 'prepare-data-bucket.sh', [
        aws_command(region,'s3api','create-bucket',*args),
        aws_command(region,'s3api','put-bucket-tagging','--bucket',name,'--tagging',json.dumps({'TagSet':tags(state['name'],'data-bucket')})),
        aws_command(region,'s3api','put-public-access-block','--bucket',name,'--public-access-block-configuration','BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'),
        aws_command(region,'s3api','put-bucket-encryption','--bucket',name,'--server-side-encryption-configuration',json.dumps({'Rules':[{'ApplyServerSideEncryptionByDefault':{'SSEAlgorithm':'AES256'}}]}))])


def sg_rules(state, filesystem=False):
    cidr = state['vpc']['CidrBlock']
    if filesystem:
        ports = [2049] if state['filesystem']['fileSystemType']=='EFS_PROVISIONED' else [22,111,443,635,2049,4045,4046]
        return [(p,cidr,'AutoMQ to file system') for p in ports]
    client_cidrs = state.get('client_cidrs', ['0.0.0.0/0'])
    result = [(r['port'], source, r['protocol']+' client access') for r in state['listeners'] for source in client_cidrs]
    result += [(22,cidr,'Console SSH management'),(9090,cidr,'Metrics collection'),(9102,cidr,'Internal broker communication'),(9103,cidr,'Internal controller communication')]
    if 'anonymous' in state.get('auth',[]): result.append((9093,cidr,'Plaintext controller communication'))
    if state.get('schema'):
        result.extend((8081, source, 'Schema Registry clients') for source in client_cidrs)
    # A client listener and an internal listener can share a port and CIDR.
    unique = {}
    for port, source, purpose in result:
        unique.setdefault((port, source), (port, source, purpose))
    return list(unique.values())


def sg_command(directory, state, purpose, rules):
    region = state['home']['region']; name = f'automq-setup-{state["name"]}-{purpose}'
    spec = [{'ResourceType':'security-group','Tags':[{'Key':'Name','Value':name}]+tags(state['name'],purpose)}]
    create = aws_command(region,'ec2','create-security-group','--group-name',name,'--description',f'AutoMQ {purpose}',
        '--vpc-id',state['vpc']['VpcId'],'--tag-specifications',json.dumps(spec),'--query','GroupId','--output','text')
    lines = ['SETUP_SG_ID=$('+create+')']
    for port,cidr,_ in rules:
        lines.append(aws_command(region,'ec2','authorize-security-group-ingress','--protocol','tcp','--port',str(port),'--cidr',cidr)+' --group-id "$SETUP_SG_ID"')
    lines.append('printf "%s\\n" "$SETUP_SG_ID"')
    return script(directory,f'prepare-{purpose}.sh',lines)


def validate_sg(group, vpc, rules):
    if group['VpcId'] != vpc: raise SetupError('Security group belongs to another VPC.')
    missing = []
    for port,cidr,purpose in rules:
        matched = False
        network = ipaddress.ip_network(cidr)
        for rule in group.get('IpPermissions',[]):
            if rule['IpProtocol'] not in ['tcp','6','-1']: continue
            if rule['IpProtocol'] != '-1' and not rule.get('FromPort',0) <= port <= rule.get('ToPort',-1): continue
            ranges = rule.get('IpRanges',[])
            matched |= any(network.subnet_of(ipaddress.ip_network(x['CidrIp'])) for x in ranges)
        if not matched: missing.append(f'TCP {port}: {purpose}, source {cidr}')
    if missing: raise SetupError('Missing inbound rules: ' + '; '.join(missing))
