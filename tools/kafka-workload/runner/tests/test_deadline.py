"""Real subprocess deadline checks; no AWS or remote resources."""
import json
import subprocess
import sys
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

from runner import api
from runner.transport import AwsSsmTransport, TransportError

RUNNER = {'region': 'us-east-1', 'instance_id': 'i-00000000', 'remote_root': '/opt/demo'}


class DeadlineTests(unittest.TestCase):
    def test_blocked_cli_process_is_killed_before_pool_join(self):
        timeouts = []
        def blocked(argv, **kwargs):
            timeouts.append(kwargs['timeout'])
            # Use the transport's actual subprocess timeout. The sleep child
            # proves ThreadPoolExecutor.__exit__ cannot hide a 40-second wait.
            return subprocess.run([sys.executable, '-c', 'import time; time.sleep(5)'], **kwargs)
        started = time.monotonic()
        deadline = started + .15
        transport = AwsSsmTransport(RUNNER, execute=blocked, deadline=deadline)
        with ThreadPoolExecutor(max_workers=2) as workers:
            tasks = [workers.submit(transport.request, 'ssm', 'get-command-invocation', {}) for _ in range(2)]
            for task in tasks:
                with self.assertRaises(TransportError): task.result()
        self.assertLess(time.monotonic() - started, 1)
        self.assertTrue(all(0 < timeout <= .15 for timeout in timeouts))
    def test_repeated_pending_ssm_stops_at_local_deadline(self):
        now = [10.0]
        calls = []
        def execute(argv, **kwargs):
            calls.append(argv)
            body = {'Command': {'CommandId': 'id'}} if 'send-command' in argv else {'Status': 'Pending'}
            return subprocess.CompletedProcess(argv, 0, json.dumps(body), '')
        transport = AwsSsmTransport(RUNNER, execute=execute, deadline=12, monotonic=lambda: now[0], sleep=lambda seconds: now.__setitem__(0, now[0] + seconds))
        with self.assertRaises(TransportError): transport.run('true', timeout_seconds=60)
        self.assertEqual(12, now[0])
        self.assertLessEqual(len(calls), 3)
    def test_expired_deadline_sends_no_request(self):
        calls = []
        transport = AwsSsmTransport(RUNNER, execute=lambda *a, **k: calls.append(a), deadline=time.monotonic() - 1)
        with self.assertRaises(TransportError): transport.request('ssm', 'send-command', {})
        self.assertEqual([], calls)
    def test_deadline_is_optional_and_wire_request_is_unchanged(self):
        from unittest.mock import patch
        request = []
        class Fake:
            def __init__(self, runner, deadline=None):
                request.append(('deadline', deadline))
            def run(self, command, timeout_seconds):
                request.append(('command', command))
                return {'schema_version': 1, 'state': 'unknown', 'frame_age_ms': None}
        with patch.object(api, 'AwsSsmTransport', Fake):
            api.snapshot(RUNNER, 'task-a', deadline=123.0)
        self.assertEqual(('deadline', 123.0), request[0])
        self.assertNotIn('deadline', request[1][1])


if __name__ == '__main__': unittest.main()
