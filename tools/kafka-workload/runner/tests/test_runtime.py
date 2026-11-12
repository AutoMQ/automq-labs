"""Security and real-process fixtures; macOS process identities are test-only.

Production uses Linux /proc start ticks, not ps timestamps.
"""
import contextlib
import hashlib
import inspect
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from runner import api
from runner.bundle import build_bundle
from runner.installer import extract_bundle, install_archive, validate_release
from runner.preflight import _java_properties, run_check
from runner.remote_agent import request_stop, snapshot_task, start_task, trusted_argv
from runner.schema import ValidationError, task_descriptor
from runner.storage import atomic, read_json
from runner.supervisor import _adopted_children_remain, accept_frame, signal_owned, supervise
from runner.transport import TransportError
CONFIG = {'schema_version': 1, 'transport': 'ssm', 'region': 'us-east-1', 'instance_id': 'i-0123456789abcdef0', 'remote_root': '/opt/client'}
FIXTURE = "#!EXECUTABLE\nimport json,signal,sys,time\nrole=sys.argv[1];topic=sys.argv[sys.argv.index('--topic')+1];seq=0;count=0\ndef emit(event,code=None):\n global seq\n seq+=1\n f=dict(schema_version=1,event=event,role=role,run_id='run',sample_seq=seq,messages=count,payload_bytes=count*100,state='running')\n if event=='ready':f['start_offsets']={'test:0':10}\n if code is not None:f.update(exit_code=code,unconfirmed_messages=1 if code else 0,state='stopped')\n print(json.dumps(f),flush=True)\ndef stopped(sig,frame):\n emit('final',4 if topic=='unconfirmed' else 0)\n sys.exit(143)\nsignal.signal(signal.SIGTERM,signal.SIG_IGN if topic=='force' else stopped)\nemit('ready')\nwhile True:\n count+=1;emit('progress');time.sleep(.05)\n".replace('EXECUTABLE', sys.executable)

ORPHAN_FIXTURE = """#!EXECUTABLE
import json,os,signal,sys,time
closed=sys.argv[sys.argv.index('--topic')+1]=='orphan-closed'
reader,writer=os.pipe()
child=os.fork()
if child==0:
 os.close(reader)
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 if closed:
  os.close(1);os.close(2)
 os.write(writer,b'x');os.close(writer)
 time.sleep(60)
 os._exit(0)
os.close(writer);os.read(reader,1);os.close(reader)
print(json.dumps(dict(schema_version=1,event='ready',role='produce',sample_seq=1,descendant_pid=child,state='ready')),flush=True)
os._exit(0)
""".replace('EXECUTABLE', sys.executable)

class ArtifactFixture(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.directory = Path(self.tmp.name).resolve()
        self.source = self.directory / 'source'
        (self.source / 'target').mkdir(parents=True)
        (self.source / 'workload').write_text(FIXTURE)
        (self.source / 'target' / 'workload.jar').write_bytes(b'fixture')
        shutil.copytree(Path(__file__).resolve().parents[1], self.source / 'runner', ignore=shutil.ignore_patterns('tests', '__pycache__'))
        if not Path('/proc/self/stat').exists():
            # Child anchor runs in a real separate interpreter. Only this test
            # bundle substitutes ps for Linux /proc; production code is unchanged.
            storage = self.source / 'runner' / 'storage.py'
            backend = '\nimport subprocess\n' + inspect.getsource(os_identity) + '\n' + inspect.getsource(os_group)
            backend += '\nprocess_identity = os_identity\ngroup_members = os_group\n'
            storage.write_text(storage.read_text() + backend)
        self.artifact = self.directory / 'runtime.tar'
        self.build = build_bundle(self.artifact, self.source)
        self.root = self.directory / 'remote'
        self.release = Path(install_archive(self.root, self.artifact, self.build['sha256'])['release'])
        self.config = self.directory / 'client.properties'
        self.config.write_text('bootstrap.servers=private:9092')
        self.config.chmod(384)

    def tearDown(self):
        self.tmp.cleanup()

    def descriptor(self, task='task', role='produce', topic='test', **extra):
        value = dict(schema_version=1, task_id=task, controller_id='controller', role=role, run_id='run', phase='before', argv=['./workload', role, '--config', str(self.config), '--topic', topic, '--run-id', 'run'])
        value.update(extra)
        return task_descriptor(value)

class BundleTests(ArtifactFixture):

    def test_deterministic_fixed_entries_exclude_credentials(self):
        (self.source / 'secret.properties').write_text('PASSWORD')
        second = self.directory / 'second.tar'
        self.assertEqual(build_bundle(second, self.source)['sha256'], self.build['sha256'])
        with tarfile.open(self.artifact) as archive:
            names = archive.getnames()
        self.assertIn('runner/remote_agent.py', names)
        self.assertIn('workload.jar', names)
        self.assertNotIn('secret.properties', names)
        self.assertEqual(self.build['manifest']['features'], ['workload'])
        for path in self.release.rglob('*'):
            self.assertEqual(path.stat().st_mode & 63, 0)
        self.assertEqual((self.root / 'current').resolve(), self.release)

    def test_bad_sha_does_not_switch_current(self):
        with self.assertRaises(ValidationError):
            install_archive(self.root, self.artifact, '0' * 64)
        self.assertEqual((self.root / 'current').resolve(), self.release)

    def test_traversal_links_special_and_duplicate_entries_refused(self):
        for i, (name, kind) in enumerate((('../escape', tarfile.REGTYPE), ('/escape', tarfile.REGTYPE), ('runner/link', tarfile.SYMTYPE), ('runner/hard', tarfile.LNKTYPE), ('runner/device', tarfile.CHRTYPE), ('runner/../escape', tarfile.REGTYPE))):
            path = self.directory / 'bad.tar'
            with tarfile.open(path, 'w') as archive:
                info = tarfile.TarInfo(name)
                info.type = kind
                info.linkname = '/etc/passwd'
                archive.addfile(info)
            with self.subTest(name=name), self.assertRaises(ValidationError):
                extract_bundle(path, self.directory / ('extract%d' % i))
        with tarfile.open(path, 'w') as archive:
            archive.addfile(tarfile.TarInfo('manifest.json'))
            archive.addfile(tarfile.TarInfo('manifest.json'))
        with self.assertRaises(ValidationError):
            extract_bundle(path, self.directory / 'duplicate')

    def test_tampered_entry_refused(self):
        (self.release / 'workload.jar').write_bytes(b'tampered')
        with self.assertRaises(ValidationError):
            validate_release(self.release)

    def test_arbitrary_command_secret_flags_and_role_mismatch_refused(self):
        for argv in (['bash', '-c', 'id'], ['./workload', 'produce', '--password', 'secret'], ['./workload', 'consume', '--config', str(self.config)]):
            with self.assertRaises(ValidationError):
                trusted_argv(self.root, self.release, self.descriptor(argv=argv))
        self.assertEqual(trusted_argv(self.root, self.release, self.descriptor())[0], str(self.release / 'workload'))

    def test_install_bootstrap_works_without_preinstalled_runner(self):
        import shlex
        binary = self.directory / 'bin'
        binary.mkdir()
        fake_aws = binary / 'aws'
        fake_aws.write_text('#!' + sys.executable + '\nimport os,shutil,sys\nshutil.copyfile(os.environ["FIXTURE_ARTIFACT"],sys.argv[4])\n')
        fake_aws.chmod(0o700)
        target = self.directory / 'bootstrap-root'
        config = dict(CONFIG, remote_root=str(target))
        class LocalTransport:
            def run(inner, command, timeout_seconds):
                self.assertLess(len(command), 64000)
                result = subprocess.run(shlex.split(command), capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                return json.loads(result.stdout)
        with patch.dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], FIXTURE_ARTIFACT=str(self.artifact)):
            result = api.install(config, 's3://private-bucket/runtime.tar', self.build['sha256'], transport=LocalTransport())
        self.assertEqual(result['sha256'], self.build['sha256'])
        self.assertEqual((target / 'current').resolve(), target / 'releases' / self.build['sha256'])

    def test_watch_requires_case_feature(self):
        with self.assertRaises(ValidationError):
            trusted_argv(self.root, self.release, self.descriptor(role='watch', argv=['python3', '-m', 'cross_az.collector', '--spec-json', '{}']))

class PropertyTests(unittest.TestCase):

    def test_escaped_keys_continuations_comments_and_last_assignment(self):
        parsed = _java_properties(b'# ignored\\\nclient.\\u0072ack : zone\nclient.id=prefix-\\\n  automq_az=zone\nx\\=key:one\nx\\=key=two\n')
        self.assertEqual(parsed['client.rack'], 'zone')
        self.assertEqual(parsed['client.id'], 'prefix-automq_az=zone')
        self.assertEqual(parsed['x=key'], 'two')
        with self.assertRaises(ValueError):
            _java_properties(b'client.\\uZZZZrack=x')

    def test_override_gate_is_boolean_without_property_values(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'config'
            path.write_bytes(b'client.\\u0072ack=PRIVATESECRET\n')
            path.chmod(384)
            value = run_check({'java': False, 'forbid_az_overrides': True, 'remote_connection_file': str(path)}, CONFIG['instance_id'], {'instanceId': CONFIG['instance_id']})
        self.assertFalse(value['ok'])
        self.assertEqual(value['permissions']['az_overrides'], {'checked': True, 'present': True})
        self.assertNotIn('PRIVATESECRET', json.dumps(value))

class FrameTests(unittest.TestCase):

    def test_ready_survives_progress_duplicate_seq_cannot_freshen(self):
        with tempfile.TemporaryDirectory() as directory:
            state = {'role': 'consume', 'state': 'running', 'frame_seq': 0}
            ready = {'schema_version': 1, 'event': 'ready', 'role': 'consume', 'sample_seq': 1, 'start_offsets': {'t:0': 10}}
            progress = dict(ready, event='progress', sample_seq=2)
            self.assertTrue(accept_frame(directory, state, json.dumps(ready), 10))
            self.assertTrue(accept_frame(directory, state, json.dumps(progress), 11))
            self.assertEqual(state['ready_frame'], ready)
            self.assertFalse(accept_frame(directory, state, json.dumps(progress), 50))
            self.assertEqual(state['frame_mono'], 11)
            self.assertEqual(read_json(Path(directory) / 'metrics.json'), progress)

    def test_subreaper_reaps_exited_children_and_waits_for_kernel_echild(self):
        with patch('runner.supervisor.os.waitpid', side_effect=[(123, 0), (0, 0)]):
            self.assertTrue(_adopted_children_remain())
        with patch('runner.supervisor.os.waitpid', side_effect=[(123, 0), ChildProcessError()]):
            self.assertFalse(_adopted_children_remain())

    def test_reused_pid_is_never_signalled(self):
        with patch('runner.supervisor.same_process', return_value=False), patch('runner.supervisor.os.killpg') as kill:
            self.assertFalse(signal_owned({'pid': 123, 'pgid': 123, 'pid_start_ticks': 111}, signal.SIGTERM))
        kill.assert_not_called()

class ApiTests(unittest.TestCase):

    def test_snapshot_conservatively_adds_rtt_without_renewing(self):
        calls = []

        class Transport:

            def run(self, command, timeout_seconds):
                import base64, shlex
                args = shlex.split(command)
                calls.append(json.loads(base64.b64decode(args[args.index('--request-b64') + 1])))
                return {'schema_version': 1, 'state': 'running', 'frame_age_ms': 14999}
        with patch('time.monotonic', side_effect=[10, 12]):
            value = api.snapshot(CONFIG, 'task', transport=Transport())
        self.assertFalse(calls[0]['renew'])
        self.assertEqual(value['frame_age_ms'], 16999)
        self.assertFalse(value['fresh'])

    def test_transport_failure_keeps_stop_identity_and_recovery(self):

        class Transport:

            def run(self, *args, **kwargs):
                raise TransportError('unavailable')
        value = api.stop(CONFIG, 'task', 'controller', transport=Transport())
        self.assertFalse(value['stop_confirmed'])
        self.assertEqual(value['task_id'], 'task')
        self.assertIn('stop --task-id task', value['recovery']['stop'])

    def test_repeated_frame_cannot_wash_staleness(self):
        values = [dict(state='running', frame_seq=1, frame_age_ms=14000), dict(state='running', frame_seq=1, frame_age_ms=0), dict(state='stopped', frame_seq=2, frame_age_ms=0)]
        with patch('runner.api.snapshot', side_effect=values), patch('time.sleep'), patch('time.monotonic', side_effect=[0, 3, 6]):
            values = list(api.attach(CONFIG, 'task', 'controller'))
        self.assertEqual(values[1]['frame_age_ms'], 17000)
        self.assertFalse(values[1]['fresh'])

def os_identity(pid):
    response = subprocess.run(['ps', '-p', str(pid), '-o', 'pgid=,state=,lstart='], capture_output=True, text=True)
    fields = response.stdout.strip().split()
    if response.returncode or len(fields) < 3 or fields[1].startswith('Z'):
        return None
    return {'pid': pid, 'pgid': int(fields[0]), 'pid_start_ticks': hash(' '.join(fields[2:]))}

def os_same(identity):
    return bool(identity and os_identity(identity.get('pid', -1)) == {k: identity.get(k) for k in ('pid', 'pgid', 'pid_start_ticks')})

def os_group(pgid):
    response = subprocess.run(['ps', '-axo', 'pid=,pgid=,state='], capture_output=True, text=True)
    if response.returncode:
        raise OSError('test group enumeration interrupted')
    result = []
    for line in response.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and int(fields[1]) == pgid and (not fields[2].startswith('Z')):
            item = os_identity(int(fields[0]))
            if item:
                result.append(item)
            else:
                try:
                    os.kill(int(fields[0]), 0)
                except ProcessLookupError:
                    continue
                raise OSError('test member enumeration interrupted')
    return result

class LifecycleTests(ArtifactFixture):

    def patches(self):
        stack = contextlib.ExitStack()
        for module in ('runner.remote_agent', 'runner.supervisor'):
            stack.enter_context(patch(module + '.boot_id', return_value='fixture-boot'))
            stack.enter_context(patch(module + '.process_identity', side_effect=os_identity))
            stack.enter_context(patch(module + '.same_process', side_effect=os_same))
        stack.enter_context(patch('runner.supervisor.group_members', side_effect=os_group))
        return stack

    def prepare(self, descriptor):
        with patch('runner.remote_agent.subprocess', SimpleNamespace(DEVNULL=subprocess.DEVNULL, Popen=lambda *a, **k: SimpleNamespace(pid=os.getpid()))):
            return start_task(str(self.root), descriptor)

    def wait_for(self, task, predicate, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = snapshot_task(str(self.root), task)
            if predicate(value):
                return value
            time.sleep(0.03)
        self.fail('state condition not reached')

    def test_anchor_does_not_launch_role_before_verified_handshake(self):
        with self.patches():
            self.prepare(self.descriptor())
        env = dict(os.environ, PYTHONPATH=str(self.release), PYTHONDONTWRITEBYTECODE='1')
        process = subprocess.Popen([sys.executable, '-m', 'runner.remote_agent', '_role', '--root', str(self.root), '--task-id', 'task'], cwd=self.release, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            time.sleep(0.15)
            self.assertIsNone(process.poll())
            self.assertFalse((self.root / 'state' / 'task' / 'role_process.json').exists())
            atomic(self.root / 'state' / 'task' / 'launch.json', {'pid': os.getpid(), 'pgid': os.getpgrp()})
            process.wait(timeout=3)
            self.assertEqual(process.returncode, 2)
            self.assertFalse((self.root / 'state' / 'task' / 'role_process.json').exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            process.stdout.close()
            process.stderr.close()

    def test_live_frames_reconnect_stop_and_role_isolation(self):
        with self.patches():
            one = self.descriptor('one', role='consume')
            self.prepare(one)
            self.prepare(self.descriptor('two'))
            threads = [threading.Thread(target=supervise, args=(str(self.root), task)) for task in ('one', 'two')]
            for thread in threads:
                thread.start()
            try:
                first = self.wait_for('one', lambda s: s.get('frame_seq', 0) >= 2)
                later = self.wait_for('one', lambda s: s.get('frame_seq', 0) > first['frame_seq'])
                self.assertEqual(first['pid'], later['pid'])
                self.assertIsNotNone(later['ready_frame'])
                self.assertEqual(start_task(str(self.root), one)['pid'], first['pid'])
                with self.assertRaises(ValidationError):
                    start_task(str(self.root), dict(one, controller_id='other'))
                before = read_json(self.root / 'state' / 'two' / 'lease.json')
                snapshot_task(str(self.root), 'one', 'controller', renew=True)
                self.assertEqual(read_json(self.root / 'state' / 'two' / 'lease.json'), before)
                with self.assertRaises(ValidationError):
                    request_stop(str(self.root), 'one', 'other')
                request_stop(str(self.root), 'one', 'controller')
                stopped = self.wait_for('one', lambda s: s['state'] in ('stopped', 'failed'))
                self.assertTrue(stopped['stop_confirmed'])
                self.assertEqual(stopped['exit_code'], 143)
                self.assertEqual(stopped['application_exit_code'], 0)
                self.assertEqual(snapshot_task(str(self.root), 'two')['state'], 'running')
            finally:
                for task in ('one', 'two'):
                    request_stop(str(self.root), task, 'controller')
                for thread in threads:
                    thread.join(15)
                self.assertTrue(all((not thread.is_alive() for thread in threads)))

    def test_max_runtime_preserves_unconfirmed_business_result_and_os_code(self):
        with self.patches():
            self.prepare(self.descriptor(topic='unconfirmed', max_runtime_seconds=1))
            thread = threading.Thread(target=supervise, args=(str(self.root), 'task'))
            thread.start()
            thread.join(7)
            self.assertFalse(thread.is_alive())
            final = snapshot_task(str(self.root), 'task')
            self.assertTrue(final['stop_confirmed'])
            self.assertEqual(final['stop_reason'], 'max_runtime_expired')
            self.assertEqual(final['exit_code'], 143)
            self.assertEqual(final['application_exit_code'], 4)
            self.assertEqual(final['last_frame']['unconfirmed_messages'], 1)
            self.assertEqual(final['state'], 'failed')

    def test_expired_lease_stops_without_poll_renewal(self):
        with self.patches():
            self.prepare(self.descriptor())
            path = self.root / 'state' / 'task' / 'lease.json'
            lease = read_json(path)
            lease['deadline'] = time.monotonic() - 0.1
            atomic(path, lease)
            thread = threading.Thread(target=supervise, args=(str(self.root), 'task'))
            thread.start()
            thread.join(7)
            self.assertFalse(thread.is_alive())
            final = snapshot_task(str(self.root), 'task')
            self.assertTrue(final['stop_confirmed'])
            self.assertEqual(final['stop_reason'], 'lease_expired')

    def orphan_lifecycle(self, closed, reconnect=False):
        (self.source / 'workload').write_text(ORPHAN_FIXTURE)
        artifact = self.directory / 'orphan.tar'
        built = build_bundle(artifact, self.source)
        install_archive(self.root, artifact, built['sha256'])
        descriptor = self.descriptor(topic='orphan-closed' if closed else 'orphan-open', max_runtime_seconds=900 if reconnect else 1)
        with self.patches():
            self.prepare(descriptor)
            thread = threading.Thread(target=supervise, args=(str(self.root), 'task'))
            started = time.monotonic()
            thread.start()
            anchor = None
            child_pid = None
            try:
                running = self.wait_for('task', lambda s: s.get('ready_frame') and (self.root / 'state' / 'task' / 'role_exit.json').exists())
                anchor = running['anchor']
                child_pid = running['ready_frame']['descendant_pid']
                self.assertNotEqual(anchor['pid'], running['pid'])
                self.assertTrue(os_same(anchor))
                self.assertIsNone(os_identity(running['pid']))
                self.assertIsNotNone(os_identity(child_pid))
                if reconnect:
                    repeated = start_task(str(self.root), descriptor)
                    self.assertEqual(repeated['anchor'], anchor)
                    self.assertFalse(repeated['stop_confirmed'])
                    request_stop(str(self.root), 'task', 'controller')
                thread.join(15)
                self.assertFalse(thread.is_alive())
                final = snapshot_task(str(self.root), 'task')
                self.assertTrue(final['stop_confirmed'])
                self.assertTrue(final['forced'])
                self.assertEqual(final['exit_code'], 137)
                self.assertEqual(final['anchor_returncode'], -signal.SIGKILL)
                self.assertEqual(final['role_os_returncode'], 0)
                self.assertEqual(final['state'], 'failed')
                self.assertFalse(os_group(anchor['pgid']))
                self.assertIsNone(os_identity(child_pid))
                self.assertLess(time.monotonic() - started, 15)
            finally:
                # A failing fixture must still clean up only its verified group.
                if anchor and os_same(anchor):
                    os.killpg(anchor['pgid'], signal.SIGKILL)
                thread.join(3)

    def test_fast_parent_exit_with_inherited_pipes_is_bounded(self):
        self.orphan_lifecycle(closed=False)

    def test_fast_parent_exit_with_closed_pipes_is_bounded(self):
        self.orphan_lifecycle(closed=True)

    def test_reconnect_stop_reuses_anchor_and_collects_orphan_group(self):
        self.orphan_lifecycle(closed=False, reconnect=True)

    def test_term_resistant_process_is_killed_after_bounded_grace(self):
        with self.patches():
            self.prepare(self.descriptor(topic='force', max_runtime_seconds=1))
            thread = threading.Thread(target=supervise, args=(str(self.root), 'task'))
            started = time.monotonic()
            thread.start()
            thread.join(16)
            self.assertFalse(thread.is_alive())
            final = snapshot_task(str(self.root), 'task')
            self.assertTrue(final['stop_confirmed'])
            self.assertTrue(final['forced'])
            self.assertEqual(final['exit_code'], 137)
            self.assertEqual(final['state'], 'failed')
            self.assertLess(time.monotonic() - started, 15)
if __name__ == '__main__':
    unittest.main()
