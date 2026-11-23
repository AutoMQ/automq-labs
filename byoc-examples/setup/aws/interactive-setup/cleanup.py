#!/usr/bin/env python3
"""Remove the cluster and new Console recorded by one setup bundle."""
import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit

from cmp_sign import CREATE_PATH, console_origin, service_credentials, signature


class CleanupError(Exception):
    pass


def document(path):
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise CleanupError(f'{path.name} must contain a JSON object.')
    return value


def require(condition, message):
    if not condition:
        raise CleanupError(message)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class CMP:
    def __init__(self, origin, credentials):
        self.origin, self.credentials = origin, credentials
        handlers = [NoRedirect()]
        if urlsplit(origin).hostname in ('127.0.0.1', 'localhost', '::1'):
            handlers.append(urllib.request.ProxyHandler({}))
        self.client = urllib.request.build_opener(*handlers)

    def request(self, method, path, *, missing_ok=False):
        stamp, auth = signature(b'', *self.credentials, datetime.now(timezone.utc), method, path)
        request = urllib.request.Request(self.origin + path, method=method,
                                         headers={'Authorization': auth, 'X-automq-date': stamp})
        try:
            with self.client.open(request, timeout=30) as response:
                body = response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            try:
                body = json.load(error)
                codes = [body.get('code'), (body.get('error') or {}).get('code')]
                code = next((code for code in codes if isinstance(code, str)), None)
            except (ValueError, TypeError, AttributeError):
                code = None
            if missing_ok and error.code == 404 and code == 'Instance.InstanceNotFound':
                return None
            detail = f' ({code})' if code and re.fullmatch(r'[A-Za-z0-9._-]+', code) else ''
            raise CleanupError(f'CMP {method} {path} returned HTTP {error.code}{detail}.') from None
        except OSError:
            raise CleanupError(f'CMP {method} {path} did not complete. Check the Console address and retry cleanup.') from None


def run_command(command, *, missing=None, timeout=45, parse_json=True):
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        code = re.search(r'\(([A-Za-z0-9._-]+)\) when calling', result.stderr)
        if missing and code and code[1] == missing:
            return None
        detail = f' ({code[1]})' if code else ''
        raise CleanupError(f'{command[0]} {command[1]} failed{detail}. Check access and retry cleanup.')
    return json.loads(result.stdout) if parse_json and result.stdout.strip() else None


class AWS:
    def __init__(self, region):
        self.region = region

    def call(self, service, action, *args, missing=None, timeout=45):
        return run_command(['aws', service, action, '--region', self.region, '--output', 'json',
                         '--no-cli-pager', '--no-cli-auto-prompt', *args], missing=missing, timeout=timeout)


def owns(resource, deployment, purpose):
    tags = {tag['Key']: tag['Value'] for tag in resource.get('Tags', [])}
    return (tags.get('automq-origin') == 'setup-command' and tags.get('automq-deployment') == deployment
            and tags.get('automq-purpose') == purpose)


class EC2Console:
    def __init__(self, aws, review, receipt):
        self.aws, self.review = aws, review
        self.instance_id = receipt['InstanceId']
        self.volume_id = receipt.get('DataVolumeId')
        require(re.fullmatch(r'i-(?:[a-f0-9]{8}|[a-f0-9]{17})', self.instance_id), 'Invalid Console EC2 instance ID.')
        self.instance = self.describe()
        if self.instance:
            require(self.instance.get('VpcId') == review['vpc'] and owns(self.instance, review['name'], 'console'),
                    'The EC2 instance does not match the setup deployment and VPC.')
            state = self.instance['State']['Name']
            if state not in ('shutting-down', 'terminated'):
                mapped = next((mapping['Ebs']['VolumeId'] for mapping in self.instance.get('BlockDeviceMappings', [])
                               if mapping['DeviceName'] == '/dev/sdf'), None)
                require(mapped and (not self.volume_id or self.volume_id == mapped),
                        'The EC2 data-volume mapping does not match its launch receipt.')
                self.volume_id = mapped
        require(not self.volume_id or re.fullmatch(r'vol-(?:[a-f0-9]{8}|[a-f0-9]{17})', self.volume_id),
                'Invalid Console data-volume ID.')
        self.volume()
        self.identity = {'kind': 'EC2', 'instanceId': self.instance_id, 'volumeId': self.volume_id}
        self.label = f'EC2 {self.instance_id} and its dedicated data volume {self.volume_id or "(already absent)"}'

    def describe(self):
        data = self.aws.call('ec2', 'describe-instances', '--instance-ids', self.instance_id,
                             missing='InvalidInstanceID.NotFound') or {}
        rows = [instance for reservation in data.get('Reservations', []) for instance in reservation['Instances']]
        return rows[0] if rows else None

    def volume(self):
        if not self.volume_id:
            return None
        data = self.aws.call('ec2', 'describe-volumes', '--volume-ids', self.volume_id,
                             missing='InvalidVolume.NotFound') or {}
        rows = data.get('Volumes', [])
        if not rows:
            return None
        volume = rows[0]
        require(owns(volume, self.review['name'], 'console-volume') and
                all(attachment['InstanceId'] == self.instance_id for attachment in volume.get('Attachments', [])),
                'The EBS volume does not belong to this Console or is attached to a different instance.')
        return volume

    def shutting_down(self):
        return self.instance is None or self.instance['State']['Name'] in ('shutting-down', 'terminated')

    def matches_metadata(self, metadata):
        return metadata.get('instanceId') == self.instance_id

    def delete(self, timeout):
        if not self.shutting_down():
            self.aws.call('ec2', 'terminate-instances', '--instance-ids', self.instance_id)
        deadline = time.monotonic() + timeout
        while True:
            instance = self.describe()
            if instance is None or instance['State']['Name'] == 'terminated':
                break
            require(time.monotonic() < deadline, 'EC2 termination is still in progress. Run cleanup again to resume.')
            time.sleep(5)
        while True:
            volume = self.volume()
            if not volume:
                return
            if volume['State'] == 'available' and not volume.get('Attachments'):
                self.aws.call('ec2', 'delete-volume', '--volume-id', self.volume_id, missing='InvalidVolume.NotFound')
                return
            require(time.monotonic() < deadline, 'The Console data volume has not detached. Run cleanup again to resume.')
            time.sleep(5)


class EKSConsole:
    def __init__(self, context, uid):
        require(re.fullmatch(r'arn:aws:eks:[a-z0-9-]+:\d{12}:cluster/[A-Za-z0-9_-]+', context or '') and
                re.fullmatch(r'[a-f0-9-]{36}', uid), 'Invalid EKS Console installation receipt.')
        self.helm = ['helm', '--kube-context', context, '--namespace', 'automq-console']
        self.kubectl = ['kubectl', '--context', context, '--namespace', 'automq-console']
        self.uid = uid
        self.identity = {'kind': 'EKS', 'context': context, 'uid': uid}
        self.label = f'Helm release automq-console/automq-console in {context}'

    def shutting_down(self):
        releases = run_command(self.helm + ['list', '--all', '--filter', '^automq-console$', '--output', 'json'])
        statefulset = run_command(self.kubectl + ['get', 'statefulset', 'automq-console', '--ignore-not-found', '-o', 'json'])
        if not releases and statefulset is None:
            return True
        require(releases and statefulset and statefulset['metadata'].get('uid') == self.uid,
                'The EKS Console release does not match its installation receipt.')
        return False

    def matches_metadata(self, metadata):
        return metadata.get('instancePlatform') == 'K8S'

    def delete(self, timeout):
        if not self.shutting_down():
            run_command(self.helm + ['uninstall', 'automq-console', '--wait', '--timeout', f'{timeout}s'],
                        timeout=timeout + 30, parse_json=False)
            require(self.shutting_down(), 'The EKS Console release still exists. Run cleanup again to resume.')


def find_receipt(bundle, override):
    if override:
        return override
    receipts = [path.parent for path in bundle.glob('*/create-response.json')]
    require(len(receipts) == 1, 'Provide --receipt with the signed bundle that contains the successful create response.')
    return receipts[0]


def require_no_other_clusters(cmp, instance_id):
    data = cmp.request('GET', CREATE_PATH)
    rows = data.get('list')
    require(isinstance(rows, list) and data.get('total') == len(rows),
            'Cannot verify that Console has no other clusters.')
    require(all(row.get('instanceId') == instance_id for row in rows),
            'Console manages other clusters. Use --cluster-only to delete this cluster and keep Console.')
    return not rows


def cleanup(args):
    bundle = args.bundle
    review = document(bundle / 'review.json')
    requested = document(bundle / 'cluster-request.json')
    receipt = find_receipt(bundle, args.receipt)
    require(document(receipt / 'request.json') == requested, 'The signed request snapshot differs from this setup bundle.')
    create = document(receipt / 'create-response.json')
    instance_id = create.get('instanceId', '')
    require(isinstance(instance_id, str) and re.fullmatch(r'kf-[a-z0-9-]+', instance_id) and
            create.get('name') == requested['name'] == review['name'],
            'The create response does not identify the cluster from this setup bundle.')
    progress_path = bundle / 'cleanup-progress.json'
    progress = document(progress_path) if progress_path.exists() else {}

    console = None
    if not args.cluster_only and review.get('consoleMode') != 'existing':
        launch = args.console_launch or bundle / 'console-launch.json'
        if args.console_launch or review.get('consoleDeploy') == 'IAAS' or (bundle / 'prepare-console-ec2.sh').is_file():
            aws = AWS(review['region'])
            require(aws.call('sts', 'get-caller-identity')['Account'] == review['account'],
                    'The active AWS identity belongs to a different account than this setup bundle.')
            launch_record = document(launch)
            previous_console = progress.get('console') or {}
            if (progress.get('environmentId') == review['environmentId'] and progress.get('clusterId') == instance_id
                    and previous_console.get('instanceId') == launch_record.get('InstanceId')):
                launch_record['DataVolumeId'] = launch_record.get('DataVolumeId') or previous_console.get('volumeId')
            console = EC2Console(aws, review, launch_record)
        elif review.get('consoleDeploy') == 'K8S' or (bundle / 'install-console-eks.sh').is_file():
            console = EKSConsole(review.get('consoleEksArn'), (bundle / 'console-eks.uid').read_text().strip())

    checkpoint = {'environmentId': review['environmentId'], 'clusterId': instance_id,
                  'console': console.identity if console else None}
    resume_console = console and console.shutting_down() and progress == checkpoint
    if not resume_console:
        origin = console_origin(args.console_url or document(receipt / 'create-target.json')['consoleUrl'])
        cmp = CMP(origin, service_credentials(bundle / 'cmp-credentials.json'))
        metadata = cmp.request('GET', '/api/v1/system/metadata')
        require(all(metadata.get(key) == value for key, value in {
            'provider': 'aws', 'environmentId': review['environmentId'], 'scope': review['account'],
            'region': review['region'], 'vpc': review['vpc'],
        }.items()), 'The reachable Console does not match this setup environment.')
        if console:
            require(console.matches_metadata(metadata), 'The reachable Console does not match its installation receipt.')
            require_no_other_clusters(cmp, instance_id)
        path = CREATE_PATH + '/' + instance_id
        cluster = cmp.request('GET', path, missing_ok=True)
        if cluster is not None:
            require(cluster.get('instanceId') == instance_id and cluster.get('name') == review['name'],
                    'The live cluster does not match its creation receipt.')

    print(f'Cluster {review["name"]} ({instance_id}): {"delete through CMP" if not resume_console and cluster is not None else "already absent"}', flush=True)
    if console:
        print(f'Console: remove {console.label} after the cluster is absent.', flush=True)
    else:
        print('Console: retain.', flush=True)
    if not args.apply:
        print('Preview only. Use --apply to execute these deletions.')
        return

    if not resume_console:
        if cluster is not None:
            if cluster.get('state') != 'Deleting':
                cmp.request('DELETE', path, missing_ok=True)
            deadline = time.monotonic() + args.timeout
            print('Waiting for CMP to finish deleting the cluster.', flush=True)
            while cmp.request('GET', path, missing_ok=True) is not None:
                require(time.monotonic() < deadline, 'CMP deletion has not finished. Run cleanup again to resume.')
                time.sleep(5)
        if console:
            require(require_no_other_clusters(cmp, instance_id), 'CMP still lists the cluster. Run cleanup again after it disappears.')
            pending = progress_path.with_suffix('.tmp')
            pending.write_text(json.dumps(checkpoint, indent=2) + '\n')
            pending.replace(progress_path)

    if console:
        console.delete(args.timeout)
    print('Cleanup complete.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, default=Path(__file__).resolve().parent, help='Setup output directory')
    parser.add_argument('--receipt', type=Path, help='Signed create directory containing its request and response')
    parser.add_argument('--console-url', help='Override the saved Console origin, including for legacy signed bundles')
    parser.add_argument('--console-launch', type=Path, help='EC2 launch JSON from a legacy bundle')
    parser.add_argument('--cluster-only', action='store_true', help='Delete only the cluster and retain Console')
    parser.add_argument('--apply', action='store_true', help='Execute deletions (default is read-only preview)')
    parser.add_argument('--timeout', type=int, default=900, help='Max seconds for each deletion stage')
    args = parser.parse_args()
    os.umask(0o077)
    try:
        require(args.timeout > 0, '--timeout must be positive.')
        if args.apply:
            with (args.bundle / '.cleanup.lock').open('a') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise CleanupError('Cleanup is already running for this bundle.') from None
                cleanup(args)
        else:
            cleanup(args)
    except CleanupError as error:
        print(error, file=sys.stderr)
        return 1
    except (OSError, ValueError, TypeError, KeyError, subprocess.SubprocessError):
        print('Cleanup stopped. Check the expected bundle files, Console connectivity, and AWS or Kubernetes access.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
