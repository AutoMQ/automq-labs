"""Read endpoint configuration and emit user-run S3 preparation commands."""
import json
from core import SetupError, aws_command, tags, write_private


def inspect_endpoints(aws, vpc_id, subnet_ids, state=None):
    tables = aws.read('ec2', 'describe-route-tables', '--filters', f'Name=vpc-id,Values={vpc_id}')['RouteTables']
    main = [t for t in tables if any(a.get('Main') for a in t.get('Associations', []))]
    associations = {}
    for subnet_id in sorted(set(subnet_ids)):
        explicit = [t for t in tables if any(a.get('SubnetId') == subnet_id for a in t.get('Associations', []))]
        matches = explicit or main
        if len(matches) != 1:
            raise SetupError(f'Cannot identify the route table associated with {subnet_id}. Check its VPC association and refresh.')
        associations[subnet_id] = matches[0]['RouteTableId']
    endpoints = aws.read('ec2', 'describe-vpc-endpoints', '--filters', f'Name=vpc-id,Values={vpc_id}')['VpcEndpoints']
    service = f'com.amazonaws.{aws.region}.s3'
    gateways = [e for e in endpoints if e.get('VpcId') == vpc_id and e.get('ServiceName') == service
                and e.get('VpcEndpointType') == 'Gateway' and e.get('State') != 'deleted']
    available = sorted([e for e in gateways if e.get('State') == 'available'], key=lambda e: e['VpcEndpointId'])
    covered = {r for e in available for r in e.get('RouteTableIds', [])}
    missing = sorted(set(associations.values()) - covered)
    # These are API dependencies for the supported EC2/EBSWAL story, not required endpoints.
    services = [('EC2', f'com.amazonaws.{aws.region}.ec2'),
                ('Auto Scaling', f'com.amazonaws.{aws.region}.autoscaling'),
                ('STS (Console identity)', 'com.amazonaws.us-east-1.sts'),
                ('IAM', 'com.amazonaws.iam'), ('Route 53', 'com.amazonaws.route53'),
                ('Pricing (CMP recommendation)', 'com.amazonaws.us-east-1.pricing.api')]
    if aws.region != 'us-east-1':
        services.append(('STS (regional AssumeRole)', f'com.amazonaws.{aws.region}.sts'))
    state = state or {}
    if state.get('deploy_type') == 'K8S' or state.get('console_deploy') == 'K8S':
        services += [('EKS', f'com.amazonaws.{aws.region}.eks'), ('EKS Auth (Pod Identity)', f'com.amazonaws.{aws.region}.eks-auth'),
                     ('Elastic Load Balancing', f'com.amazonaws.{aws.region}.elasticloadbalancing')]
    if state.get('filesystem'):
        fs = 'elasticfilesystem' if state['filesystem']['fileSystemType'] == 'EFS_PROVISIONED' else 'fsx'
        services.append((fs, f'com.amazonaws.{aws.region}.{fs}'))
    if state.get('metrics', {}).get('authType') == 'sigv4':
        services.append(('AMP Remote Write', f'com.amazonaws.{aws.region}.aps-workspaces'))
    interfaces = []
    for label, name in services:
        found = [e for e in endpoints if e.get('VpcId') == vpc_id and e.get('ServiceName') == name
                 and e.get('VpcEndpointType') == 'Interface' and e.get('State') != 'deleted']
        interfaces.append({'service': label, 'serviceName': name, 'endpoints': [
            {'id': e['VpcEndpointId'], 'state': e.get('State'), 'privateDnsEnabled': e.get('PrivateDnsEnabled', False)} for e in found]})
    return {'subnetRouteTables': associations, 's3Service': service,
            's3Gateways': available, 's3MissingRouteTables': missing,
            's3Unready': [{'id': e['VpcEndpointId'], 'state': e.get('State')} for e in gateways if e.get('State') != 'available'],
            'interfaces': interfaces, 'connectivity': 'not tested', 'endpointPolicy': 'requires user review'}


def s3_command(directory, state, result):
    path = directory / 'prepare-s3-endpoint.sh'
    path.unlink(missing_ok=True)  # Never leave a stale create command after a refresh.
    missing = result['s3MissingRouteTables']
    if not missing or result['s3Unready']:
        return None
    region = state['home']['region']
    if result['s3Gateways']:
        command = aws_command(region, 'ec2', 'modify-vpc-endpoint', '--vpc-endpoint-id',
                              result['s3Gateways'][0]['VpcEndpointId'], '--add-route-table-ids', *missing)
    else:
        resource_tags = [{'Key': 'Name', 'Value': f'automq-setup-{state["name"]}-s3-endpoint'}] + tags(state['name'], 's3-endpoint')
        command = aws_command(region, 'ec2', 'create-vpc-endpoint', '--vpc-id', state['vpc']['VpcId'],
            '--vpc-endpoint-type', 'Gateway', '--service-name', result['s3Service'], '--route-table-ids', *missing,
            '--client-token', f'{state["name"]}-{state["vpc"]["VpcId"]}-s3',
            '--tag-specifications', json.dumps([{'ResourceType': 'vpc-endpoint', 'Tags': resource_tags}]))
    write_private(path, '#!/usr/bin/env bash\nset -euo pipefail\n' + command + '\n')
    return path
