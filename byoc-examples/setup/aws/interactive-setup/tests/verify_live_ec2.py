#!/usr/bin/env python3
"""Verify the live CMP and AWS resources for a completed EC2 case."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cleanup import AWS, CMP, CleanupError, document, find_receipt, require
from cmp_sign import CREATE_PATH, console_origin, service_credentials
from model import listeners


def verify_file_systems(aws, cmp, path, expected):
    rows = cmp.request('GET', path + '/file-systems')['list']
    require(len(rows) == expected['fileSystemCount'], 'CMP returned a different file system count.')
    for row in rows:
        require(row['fileSystemType'] == expected['fileSystemType']
                and row['throughputInMiBps'] == expected['throughputMiBpsPerFileSystem'],
                'The file system type or throughput differs from the signed request.')
        if expected.get('securityGroups'):
            require(set(row['securityGroups']) == set(expected['securityGroups']),
                    'CMP is using different file system security groups.')
        if row['fileSystemType'] == 'EFS_PROVISIONED':
            file_id = row['fileSystemId']
            fs, = aws.call('efs', 'describe-file-systems', '--file-system-id', file_id)['FileSystems']
            require(fs['LifeCycleState'] == 'available' and fs['Encrypted']
                    and fs['ProvisionedThroughputInMibps'] == row['throughputInMiBps'],
                    f'EFS {file_id} does not match the expected state, encryption, or throughput.')
            targets = aws.call('efs', 'describe-mount-targets', '--file-system-id', file_id)['MountTargets']
            require({target['SubnetId'] for target in targets} == set(expected['subnetIds'])
                    and all(target['LifeCycleState'] == 'available' for target in targets),
                    f'EFS {file_id} mount targets do not match the selected subnets or are still provisioning.')
    return [row['fileSystemId'] for row in rows]


def verify(args):
    bundle = args.bundle
    review = document(bundle / 'review.json')
    receipt = find_receipt(bundle, args.receipt)
    request = document(receipt / 'request.json')
    response = document(receipt / 'create-response.json')
    instance_id = response.get('instanceId', '')
    require(re.fullmatch(r'kf-[a-z0-9-]+', instance_id)
            and response.get('name') == request['name'] == review['name']
            and request == document(bundle / 'cluster-request.json'),
            'The create receipt does not match this setup bundle.')
    expected = request['spec']
    require(expected['deployType'] == 'IAAS' and expected['provider'] == 'aws',
            'Select the receipt for an AWS EC2 cluster.')

    origin = console_origin(args.console_url or document(receipt / 'create-target.json')['consoleUrl'])
    cmp = CMP(origin, service_credentials(bundle / 'cmp-credentials.json'))
    identity = {'provider': 'aws', 'environmentId': review['environmentId'], 'scope': review['account'],
                'region': review['region'], 'vpc': review['vpc']}
    metadata = cmp.request('GET', '/api/v1/system/metadata')
    require(all(metadata.get(key) == value for key, value in identity.items()),
            'The reachable Console does not match this setup environment.')
    aws = AWS(review['region'])
    require(aws.call('sts', 'get-caller-identity')['Account'] == review['account'],
            'The AWS CLI identity belongs to a different account than this setup bundle.')
    path = CREATE_PATH + '/' + instance_id
    cluster = cmp.request('GET', path)
    require(cluster['name'] == request['name'] and cluster['instanceId'] == instance_id,
            'CMP returned a different cluster.')
    require(cluster['state'] == 'Running', 'The cluster has not reached Running. Check its task in Console.')
    spec, features = cluster['spec'], cluster['features']
    require(all(spec.get(key) == expected[key] for key in ('vpc', 'region', 'scope', 'instanceRole', 'deployType'))
            and cluster['version'] == request['version'] and features['walMode'] == request['features']['walMode'],
            'CMP settings differ from the signed create request.')
    data_buckets = bucket_names(spec)
    if expected['dataBuckets']:
        require(data_buckets == bucket_names(expected) and not spec['managedDataBuckets'],
                'CMP did not reuse the selected data bucket.')
    else:
        require(data_buckets and spec['managedDataBuckets'], 'CMP did not create a managed data bucket.')
    for bucket in sorted(data_buckets):
        aws.call('s3api', 'head-bucket', '--bucket', bucket, '--expected-bucket-owner', review['account'])
    require(spec.get('dnsZone') and
            (spec.get('dnsZoneType') == 'PUBLIC' if expected.get('dnsZoneType') == 'PUBLIC'
             else spec['dnsZone'] == expected['dnsZone']),
            'CMP did not use the expected DNS zone.')

    network = {row['subnet']: row['zone'] for row in expected['networks']}
    brokers = aws.call('ec2', 'describe-instances', '--filters', f'Name=vpc-id,Values={expected["vpc"]}',
                       f'Name=tag:automqInstanceID,Values={instance_id}', 'Name=instance-state-name,Values=running',
                       '--query', 'Reservations[].Instances[]')
    count = expected['reservedNodeCount']
    require(len(brokers) == count and
            Counter(broker['SubnetId'] for broker in brokers) == {subnet: count // len(network) for subnet in network},
            'The EC2 brokers are not running in the requested subnet layout.')
    profiles = aws.call('iam', 'list-instance-profiles-for-role', '--role-name', expected['instanceRole'])['InstanceProfiles']
    profile_arns = {profile['Arn'] for profile in profiles}
    expected_groups = set(expected.get('securityGroups') or spec['brokerSecurityGroups'])
    require(expected_groups and (bool(expected.get('securityGroups')) != spec['managedSecurityGroup']),
            'CMP did not use the requested security group ownership.')
    for broker in brokers:
        groups = {group['GroupId'] for group in broker['SecurityGroups']}
        require(broker['Placement']['AvailabilityZone'] == network[broker['SubnetId']]
                and broker['InstanceType'] in expected['nodeConfig']['instanceTypes']
                and expected_groups.issubset(groups)
                and (broker.get('IamInstanceProfile') or {}).get('Arn') in profile_arns,
                f'EC2 broker {broker["InstanceId"]} differs from the requested placement, type, security groups, or IAM role.')
    broker_ids = sorted(broker['InstanceId'] for broker in brokers)
    status = aws.call('ec2', 'describe-instance-status', '--instance-ids', *broker_ids)['InstanceStatuses']
    healthy = {row['InstanceId'] for row in status
               if row['SystemStatus']['Status'] == row['InstanceStatus']['Status'] == 'ok'}
    require(healthy == set(broker_ids), 'EC2 status checks have not passed for all brokers. Run verification again.')

    security = request['features']['security']
    expected_ports = {row['protocol']: row['port']
                      for row in listeners(security['transitEncryptionModes'], security['authenticationMethods'])}
    endpoints = {row['protocol']: row['bootstrapServers']
                 for row in cmp.request('GET', path + '/endpoints')['list']}
    require(set(endpoints) == set(expected_ports), 'CMP does not expose the requested Kafka protocols.')
    for protocol, endpoint in endpoints.items():
        require(endpoint and all(host.endswith(f':{expected_ports[protocol]}') for host in endpoint.split(',')),
                f'The CMP endpoint for {protocol} does not use the expected port.')
    file_system = expected.get('fileSystemForFsWal')
    return {'name': request['name'], 'instanceId': instance_id, 'state': 'Running', 'brokerInstanceIds': broker_ids,
            'dataBuckets': sorted(data_buckets), 'dnsZone': spec['dnsZone'], 'endpoints': endpoints,
            'fileSystems': verify_file_systems(aws, cmp, path, file_system) if file_system else []}


def bucket_names(spec):
    return {row['bucketName'] for row in spec['dataBuckets']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True, help='Original setup output directory')
    parser.add_argument('--receipt', type=Path, help='Signed create directory when the bundle has multiple receipts')
    parser.add_argument('--console-url', help='Console origin reachable from this machine')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args), indent=2))
        return 0
    except (CleanupError, ValueError, KeyError, OSError, subprocess.TimeoutExpired) as error:
        print(f'EC2 verification failed. {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
