import argparse
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cleanup import CMP, CleanupError, EKSConsole, cleanup


INSTANCE = 'i-0123456789abcdef0'
VOLUME = 'vol-0123456789abcdef0'
CLUSTER = 'kf-test-cluster'
NAME = 'cleanup-test'
ACCOUNT = '123456789012'
VPC = 'vpc-test'
ENVIRONMENT = 'env-test'


def tags(purpose):
    return [{'Key': key, 'Value': value} for key, value in {
        'automq-origin': 'setup-command', 'automq-deployment': NAME, 'automq-purpose': purpose,
    }.items()]


class FakeDeployment:
    def __init__(self):
        self.events = []
        self.cluster_state = 'Running'
        self.console_state = 'running'
        self.volume_exists = True
        self.other_clusters = False
        self.delete_error = None
        self.owner_tags = tags('console')

    def request(self, method, path, missing_ok=False):
        self.events.append((method, path))
        if path == '/api/v1/system/metadata':
            return {'provider': 'aws', 'environmentId': ENVIRONMENT, 'scope': ACCOUNT, 'region': 'us-east-1',
                    'vpc': VPC, 'instanceId': INSTANCE}
        if path == '/api/v1/instances':
            rows = [{'instanceId': CLUSTER}] if self.cluster_state else []
            if self.other_clusters:
                rows.append({'instanceId': 'kf-neighbor'})
            return {'total': len(rows), 'list': rows}
        if method == 'DELETE':
            if self.delete_error:
                raise self.delete_error
            self.cluster_state = None
            return {}
        if self.cluster_state is None:
            return None
        return {'name': NAME, 'instanceId': CLUSTER, 'state': self.cluster_state}

    def call(self, service, action, *args, **kwargs):
        self.events.append((service, action))
        if action == 'get-caller-identity':
            return {'Account': ACCOUNT}
        if action == 'describe-instances':
            return {'Reservations': [{'Instances': [{'InstanceId': INSTANCE, 'VpcId': VPC, 'Tags': self.owner_tags,
                'State': {'Name': self.console_state},
                'BlockDeviceMappings': [{'DeviceName': '/dev/sdf', 'Ebs': {'VolumeId': VOLUME}}]}]}]}
        if action == 'describe-volumes':
            if not self.volume_exists:
                return None
            attached = self.console_state != 'terminated'
            return {'Volumes': [{'Tags': tags('console-volume'), 'State': 'in-use' if attached else 'available',
                                 'Attachments': [{'InstanceId': INSTANCE}] if attached else []}]}
        if action == 'terminate-instances':
            assert args == ('--instance-ids', INSTANCE)
            self.console_state = 'terminated'
        elif action == 'delete-volume':
            assert args == ('--volume-id', VOLUME)
            assert self.console_state == 'terminated'
            self.volume_exists = False
        else:
            raise AssertionError(action)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.bundle = Path(self.tmp.name)
        self.receipt = self.bundle / 'signed-create'
        self.receipt.mkdir()
        for path, data in {
            self.bundle / 'review.json': {'name': NAME, 'environmentId': ENVIRONMENT, 'account': ACCOUNT, 'region': 'us-east-1',
                                          'vpc': VPC, 'consoleMode': 'new', 'consoleDeploy': 'IAAS'},
            self.bundle / 'cluster-request.json': {'name': NAME},
            self.receipt / 'request.json': {'name': NAME},
            self.receipt / 'create-response.json': {'name': NAME, 'instanceId': CLUSTER},
            self.receipt / 'create-target.json': {'consoleUrl': 'http://127.0.0.1:8080'},
            self.bundle / 'console-launch.json': {'InstanceId': INSTANCE, 'DataVolumeId': VOLUME},
            self.bundle / 'cmp-credentials.json': {'accessKey': 'TestAccess', 'secretKey': 'TestSecret'},
        }.items():
            path.write_text(json.dumps(data))
        self.args = argparse.Namespace(bundle=self.bundle, receipt=None, console_url=None, console_launch=None,
                                       cluster_only=False, apply=False, timeout=5)
        self.deployment = FakeDeployment()
        self.checkpoint = self.bundle / 'cleanup-progress.json'

    def run_cleanup(self):
        with patch('cleanup.AWS', return_value=self.deployment), patch('cleanup.CMP', return_value=self.deployment):
            with redirect_stdout(io.StringIO()) as output:
                cleanup(self.args)
            return output.getvalue()

    def test_default_preview_only_reads(self):
        output = self.run_cleanup()
        self.assertIn(CLUSTER, output)
        self.assertIn(INSTANCE, output)
        self.assertIn(VOLUME, output)
        self.assertIn('Preview only', output)
        self.assertFalse(self.checkpoint.exists())
        self.assertNotIn(('DELETE', '/api/v1/instances/' + CLUSTER), self.deployment.events)
        self.assertNotIn(('ec2', 'terminate-instances'), self.deployment.events)

    def test_cluster_is_confirmed_absent_before_ec2_and_volume_deletion(self):
        self.args.apply = True
        self.run_cleanup()
        events = self.deployment.events
        delete = events.index(('DELETE', '/api/v1/instances/' + CLUSTER))
        terminate = events.index(('ec2', 'terminate-instances'))
        volume = events.index(('ec2', 'delete-volume'))
        self.assertLess(delete, terminate)
        self.assertIn(('GET', '/api/v1/instances/' + CLUSTER), events[delete:terminate])
        self.assertLess(terminate, volume)
        self.assertTrue(self.checkpoint.is_file())
        self.deployment.events.clear()
        self.run_cleanup()
        self.assertTrue(all(call[0] not in ('GET', 'DELETE') for call in self.deployment.events))

    def test_failed_cluster_delete_leaves_console(self):
        self.args.apply = True
        self.deployment.delete_error = CleanupError('CMP rejected deletion.')
        with self.assertRaisesRegex(CleanupError, 'rejected'):
            self.run_cleanup()
        self.assertFalse(self.checkpoint.exists())
        self.assertNotIn(('ec2', 'terminate-instances'), self.deployment.events)

    def test_console_managing_other_clusters_requires_cluster_only(self):
        self.args.apply = True
        self.deployment.other_clusters = True
        with self.assertRaisesRegex(CleanupError, 'other clusters'):
            self.run_cleanup()
        self.assertFalse(any(event[0] == 'DELETE' for event in self.deployment.events))
        self.args.cluster_only = True
        self.run_cleanup()
        self.assertIsNone(self.deployment.cluster_state)
        self.assertEqual(self.deployment.console_state, 'running')

    def test_unowned_console_is_rejected_before_cluster_mutation(self):
        self.args.apply = True
        self.deployment.owner_tags = []
        with self.assertRaisesRegex(CleanupError, 'does not match'):
            self.run_cleanup()
        self.assertFalse(any(event[0] == 'DELETE' for event in self.deployment.events))

    def test_cmp_distinguishes_missing_cluster_from_other_404_responses(self):
        cmp = CMP('http://127.0.0.1:8080', ('TestAccess', 'TestSecret'))
        path = '/api/v1/instances/' + CLUSTER
        missing = urllib.error.HTTPError(cmp.origin + path, 404, 'Not Found', {},
                                        io.BytesIO(b'{"error":{"code":"Instance.InstanceNotFound"}}'))
        wrong_route = urllib.error.HTTPError(cmp.origin + path, 404, 'Not Found', {},
                                            io.BytesIO(b'{"error":{"code":"NotFound"}}'))
        with patch.object(cmp.client, 'open', side_effect=[missing, wrong_route]) as send:
            self.assertIsNone(cmp.request('GET', path, missing_ok=True))
            with self.assertRaisesRegex(CleanupError, 'HTTP 404'):
                cmp.request('DELETE', path, missing_ok=True)
        request = send.call_args.args[0]
        self.assertEqual(request.get_method(), 'DELETE')
        self.assertTrue(request.get_header('Authorization').startswith('AUTOMQ-HMAC-SHA256'))

    def test_eks_helm_uninstall_checks_the_original_workload_uid(self):
        context = 'arn:aws:eks:us-east-1:123456789012:cluster/test'
        uid = '01234567-89ab-cdef-0123-456789abcdef'
        console = EKSConsole(context, uid)
        release = [{'name': 'automq-console'}]
        replacement = {'metadata': {'uid': '00000000-0000-0000-0000-000000000000'}}
        with patch('cleanup.run_command', side_effect=[release, replacement]) as run:
            with self.assertRaisesRegex(CleanupError, 'does not match'):
                console.delete(5)
            self.assertEqual(run.call_count, 2)
        original = {'metadata': {'uid': uid}}
        with patch('cleanup.run_command', side_effect=[release, original, None, [], None]) as run:
            console.delete(5)
        self.assertIn('uninstall', run.call_args_list[2].args[0])
        self.assertIn('--wait', run.call_args_list[2].args[0])
