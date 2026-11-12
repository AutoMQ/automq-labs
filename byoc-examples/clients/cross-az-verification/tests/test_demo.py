"""Cloud-free lifecycle tests with independent remote task simulations."""
import contextlib
import copy
import io
import json
import pathlib
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from cross_az import demo

HERE = pathlib.Path(__file__).resolve().parent.parent
REAL = demo.runner_api()
CaseError = demo.CaseError


class Clock:
    def __init__(self): self.now = 100.0
    def __call__(self): return self.now
    def sleep(self, seconds): self.now += seconds


class Remote:
    load_runner = staticmethod(REAL.load_runner)
    def __init__(self, clock):
        self.clock = clock
        self.jobs, self.events, self.polls = {}, [], {}
        self.unknown, self.readiness, self.renewals = set(), {}, []
        self.stopped = set()
        self.cleanup_exits = {}
        self.fail_role = self.interrupt_role = None
        self.cleanup_reject = self.incomplete = False
        self.slow = 0
    def check(self, runner, requirements, **kw):
        config = json.loads(pathlib.Path(runner).read_text())
        client = config['profile']
        return {'ok': True, 'identity': {'identity_verified': True, 'instance_id': config['instance_id'], 'hostname': client, 'zone_id': 'example-az1', 'private_ip': '10.40.1.' + str(10 + ord(client[-1]) - ord('a'))}, 'permissions': {'az_overrides': {'checked': True, 'present': False}}}
    def start(self, runner, descriptor, **kw):
        key = descriptor['task_id']
        self.jobs[key] = (copy.deepcopy(runner), copy.deepcopy(descriptor))
        self.events.append(('start', descriptor['role'], runner['profile'], key))
        if descriptor['role'] == 'scope-cleanup':
            self.cleanup_exits[key] = 2 if self.cleanup_reject else 0
        if descriptor['role'] == 'produce':
            consumers = [d for _, d in self.jobs.values() if d['role'] == 'consume' and d['phase'] == descriptor['phase']]
            assert len(consumers) == self.expected_clients
            assert all(self.readiness.get(d['task_id']) for d in consumers), 'producer preceded full ready barrier'
        if descriptor['role'] == self.interrupt_role:
            self.interrupt_role = None
            raise KeyboardInterrupt()
        if descriptor['role'] == self.fail_role:
            self.unknown.add(key)
            raise OSError('ack lost')
        return {'state': 'starting'}
    def snapshot(self, runner, task_id, controller_id=None, renew=False, **kw):
        self.clock.now += self.slow
        if renew: self.renewals.append(task_id)
        if task_id in self.unknown: return {'state': 'unknown', 'stop_confirmed': False}
        _, descriptor = self.jobs[task_id]
        role, client = descriptor['role'], runner['profile']
        self.polls[task_id] = self.polls.get(task_id, 0) + 1
        frame = {'event': 'progress', 'run_id': 'unused', 'role': role}
        terminal = role in ('topic', 'scope-prepare', 'scope-cleanup', 'produce')
        result = {'state': 'stopped' if terminal else 'running', 'stop_confirmed': terminal, 'exit_code': 0 if terminal else None, 'application_exit_code': 0 if terminal else None, 'task_id': task_id, 'frame_seq': self.polls[task_id], 'frame_age_ms': 0}
        if role.startswith('scope-'):
            frame['result'] = {'state': 'prepared' if role == 'scope-prepare' else 'cleaned', 'namespace': 'ns-' + client, 'source_proof': {'verified': True}}
            if role == 'scope-cleanup':
                result['exit_code'] = self.cleanup_exits[task_id]
                if result['exit_code']:
                    frame['result']['state'] = 'cleanup_incomplete'
        elif role in ('produce', 'consume'):
            index = ord(client[-1]) - ord('a')
            phase_id = 'az-' + demo.fingerprint({'run_id': descriptor['run_id'], 'phase': descriptor['phase']})[:32] + '-' + descriptor['phase']
            frame.update(run_id=phase_id, messages=600 if role == 'produce' else 600 * self.expected_clients, payload_bytes=614400, errors=0)
            if role == 'produce':
                frame.update(event='final', max_acked_offsets={'demo:0': (index + 1) * 600 - 1}, unconfirmed_messages=0)
            else:
                frame.update(next_offsets={'demo:0': 600 * self.expected_clients})
                ready = {'event': 'ready', 'run_id': phase_id, 'start_offsets': {'demo:0': 0}}
                self.readiness[task_id] = client != 'client-b' or self.polls[task_id] >= 2
                if self.readiness[task_id]: result['ready_frame'] = ready
        elif role == 'watch':
            frame = self.business()
            frame.update(client_id=client, phase=descriptor['phase'])
            frame['retained_window'] = self.business()
        result['last_frame'] = frame
        if task_id in self.stopped and not terminal:
            result.update(state='stopped', stop_confirmed=True, exit_code=0, application_exit_code=0)
        return result
    def business(self):
        return {'sample_seq': 3, 'sample_time': 'original-business-time', 'window_seconds': 10, 'elapsed_seconds': 30, 'warmup_seconds': 10, 'capture_frame_age_ms': 0,
                'quality': {'complete': not self.incomplete, 'source_verified': True, 'scope_intact': True, 'kernel_drops': 0, 'queue_drops': 0, 'parse_errors': 0},
                'window': {r: {'tx_bytes': 41 if r == 'cross' else 100 if r == 'same' else 0, 'rx_bytes': 0} for r in ('same', 'cross', 'unknown')}, 'totals': {},
                'workload': {'produce_active': True, 'consume_active': True, 'frames_fresh': True, 'window_success': {r: {'messages': 90, 'payload_bytes': 92160, 'covered_seconds': 9} for r in ('produce', 'consume')}}}
    def stop(self, runner, task_id, controller_id, **kw):
        self.events.append(('stop', self.jobs[task_id][1]['role'], runner['profile'], task_id))
        if task_id in self.unknown: return {'state': 'unknown', 'stop_confirmed': False}
        self.stopped.add(task_id)
        return {'state': 'stopped', 'stop_confirmed': True, 'exit_code': self.cleanup_exits.get(task_id, 0)}


class DemoTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.config = self.root / 'case.json'
        self.case = json.loads((HERE / 'examples/case.json').read_text())
        self.case['topic'] = 'demo'
        self.case['workload']['partitions'] = 1
        self.case['clients'] = {f'client-{c}': dict(self.case['clients']['client-a'], source_ip='10.40.1.' + str(10 + i), runner_file=f'{c}.json') for i, c in enumerate('abc')}
        for i, c in enumerate('abc'):
            runner = json.loads((HERE / 'examples/runner-a.json').read_text())
            runner.update(region='us-east-1', profile='client-' + c, instance_id='i-' + str(i + 1) * 8)
            (self.root / (c + '.json')).write_text(json.dumps(runner))
        self.config.write_text(json.dumps(self.case))
        self.clock = Clock()
        self.api = Remote(self.clock)
        self.api.expected_clients = 3
        self.store = demo.Store(self.root / 'state')
    def begin(self, phase='before', clients=None):
        return demo.begin(self.store, self.config, clients, phase, self.api)
    def round(self, directory, phase='before'):
        return demo.Round(self.store, directory, phase, self.api, self.clock, self.clock.sleep, lambda text: None)
    def test_full_cohort_barrier_full_drain_retained_and_pairing(self):
        directory = self.begin()
        run = self.round(directory)
        run.run()
        self.assertEqual('Succeeded', run.phase_state()['status'])
        for c in self.case['clients']:
            evidence = json.loads(run.controllers[c].path(c, 'before', 'baseline').read_text())
            self.assertEqual('original-business-time', evidence['sample_time'])
            self.assertEqual({'demo:0': 1800}, evidence['target_next_offsets'])
            self.assertTrue(evidence['drained'])
            consume = run.job(c, 'consume')['descriptor']['argv']
            self.assertNotIn('--max-messages', consume)
            self.assertNotIn('--duration-seconds', consume)
        before_tasks = set(self.api.jobs)
        self.begin('after')
        after = self.round(directory, 'after')
        after.run()
        self.assertTrue(before_tasks.isdisjoint({j['descriptor']['task_id'] for j in after.phase_state()['jobs'].values()}))
        with self.assertRaises(CaseError): self.begin('after')
        self.assertNotEqual(directory, self.begin())
        self.assertEqual(self.case['run_id'], json.loads(self.config.read_text())['run_id'])
    def test_lost_ack_keeps_identity_blocks_cleanup_and_new_round(self):
        run = self.round(self.begin())
        self.api.fail_role = 'consume'
        with self.assertRaises(CaseError): run.run()
        self.assertEqual('Recovery required', run.phase_state()['status'])
        self.assertFalse(any(e[1] == 'scope-cleanup' for e in self.api.events))
        self.assertTrue(all(j['descriptor']['controller_id'] for j in run.phase_state()['jobs'].values()))
        with self.assertRaises(CaseError): self.begin()
        self.api.unknown.clear()
        self.api.fail_role = None
        self.assertTrue(run.teardown())
        self.assertTrue(run.teardown())
        self.assertEqual(3, sum(e[0:2] == ('start', 'scope-cleanup') for e in self.api.events))
    def test_interrupt_stops_every_started_role(self):
        run = self.round(self.begin())
        self.api.interrupt_role = 'produce'
        with self.assertRaises(CaseError): run.run()
        started = {e[3] for e in self.api.events if e[0] == 'start' and e[1] != 'scope-cleanup'}
        stopped = {e[3] for e in self.api.events if e[0] == 'stop'}
        self.assertEqual(started, stopped)
        self.assertEqual('Failed', run.phase_state()['status'])
    def test_frozen_target_and_after_input_change(self):
        run = self.round(self.begin())
        run.run()
        path = self.root / 'a.json'
        target = json.loads(path.read_text())
        target['instance_id'] = 'i-99999999'
        path.write_text(json.dumps(target))
        with self.assertRaises(CaseError): self.begin('after')
        self.assertTrue(run.teardown())
        self.assertEqual('i-11111111', run.job('client-a', 'produce')['runner']['instance_id'])
    def test_empty_preparing_claim_and_owner_lock_block_second_start(self):
        directory = self.begin()
        with self.assertRaises(CaseError): self.begin()
        with self.store.lock('phase-owner', blocking=False):
            with self.assertRaises(CaseError):
                with self.store.lock('phase-owner', blocking=False): pass
        run = self.round(directory)
        self.assertTrue(run.teardown())
        run.change(status='Failed')
        self.assertNotEqual(directory, self.begin())
    def test_stop_intent_blocks_business_allows_safe_cleanup(self):
        run = self.round(self.begin())
        for c in run.cohort:
            run.controllers[c].check()
            run.submit(c, 'scope-prepare')
        run.change(stop_requested=True)
        with self.assertRaises(CaseError): run.submit('client-a', 'watch')
        with self.assertRaises(CaseError): run.submit('client-a', 'scope-cleanup', maintenance=True)
        self.assertTrue(run.teardown())
    def test_capture_failure_and_cleanup_rejection_cannot_succeed(self):
        run = self.round(self.begin())
        self.api.incomplete = self.api.cleanup_reject = True
        with self.assertRaises(CaseError): run.run()
        self.assertFalse(any(e[1] == 'produce' for e in self.api.events))
        self.assertEqual('Recovery required', run.phase_state()['status'])
        self.assertLessEqual(self.clock.now, 100 + 900 + 180)
    def test_status_is_read_only_and_uses_saved_input(self):
        directory = self.begin()
        self.round(directory).run()
        self.config.unlink()
        self.api.renewals.clear()
        with contextlib.redirect_stdout(io.StringIO()):
            code = demo.main(['status', '--config', str(self.config), '--state-dir', str(self.store.root)], api=self.api)
        self.assertEqual(0, code)
        self.assertEqual([], self.api.renewals)
    def test_completed_stop_preserves_both_successful_phases(self):
        directory = self.begin()
        self.round(directory).run()
        args = ['--config', str(self.config), '--state-dir', str(self.store.root)]
        with contextlib.redirect_stdout(io.StringIO()):
            with patch.object(self.api, 'stop', side_effect=AssertionError('completed stop must not contact remote')):
                self.assertEqual(0, demo.main(['stop'] + args, api=self.api))
        self.assertEqual('Succeeded', self.store.read(directory)['phases']['before']['status'])
        self.begin('after')
        self.round(directory, 'after').run()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, demo.main(['stop'] + args, api=self.api))
        self.assertEqual('Succeeded', self.store.read(directory)['phases']['after']['status'])
    def test_failed_writer_is_stopped_without_baseline(self):
        run = self.round(self.begin())
        original = self.api.snapshot
        def faulty(runner, task, **kwargs):
            result = original(runner, task, **kwargs)
            if self.api.jobs[task][1]['role'] == 'produce':
                result['last_frame']['unconfirmed_messages'] = 1
            return result
        self.api.snapshot = faulty
        with self.assertRaises(CaseError): run.run()
        self.assertEqual('Failed', run.phase_state()['status'])
        self.assertFalse(any(p.name.endswith('-baseline.json') for p in (run.directory / 'roles').iterdir()))
    def test_repeated_frame_does_not_become_young_again(self):
        run = self.round(self.begin())
        controller = run.controllers['client-a']
        controller.check()
        run.submit('client-a', 'scope-prepare')
        original = self.api.snapshot
        def repeated(*args, **kwargs):
            result = original(*args, **kwargs)
            result['frame_seq'] = 1
            return result
        self.api.snapshot = repeated
        job = run.job('client-a', 'scope-prepare')
        self.assertEqual(0, run.sample_one(job)['frame_age_ms'])
        self.clock.now += 16
        self.assertGreater(run.sample_one(job)['frame_age_ms'], 15000)
    def test_slow_pool_samples_are_aged_at_decision_time(self):
        run = self.round(self.begin())
        for c in run.cohort:
            run.controllers[c].check()
            run.submit(c, 'scope-prepare')
            run.submit(c, 'consume')
        self.api.slow = 10
        sampled = run.sample()
        missing = demo.ready_barrier({c: run.aged(sampled[c + '/consume']) for c in run.cohort}, 1, 'demo', demo.phase_run_id(run.case, 'before'))
        self.assertIn('client-a', missing)
        self.assertFalse(any(e[1] == 'produce' for e in self.api.events))
    def test_expired_execution_runs_bounded_empty_cleanup(self):
        run = self.round(self.begin())
        run.deadline = self.clock() - 1
        with self.assertRaises(CaseError): run.run()
        self.assertEqual('Failed', run.phase_state()['status'])
        self.assertEqual([], self.api.events)
    def test_stop_failure_still_attempts_every_owned_task(self):
        run = self.round(self.begin())
        for c in run.cohort:
            run.controllers[c].check()
            run.submit(c, 'scope-prepare')
        original = self.api.stop
        attempted = []
        def faulty(runner, task, controller_id, **kwargs):
            attempted.append(task)
            if runner['profile'] == 'client-a': raise OSError('unavailable')
            return original(runner, task, controller_id, **kwargs)
        self.api.stop = faulty
        self.assertFalse(run.teardown())
        self.assertEqual(3, len(attempted))
        self.assertFalse(any(e[1] == 'scope-cleanup' for e in self.api.events))
    def test_cleanup_timeout_stops_owned_maintenance_and_keeps_recovery(self):
        run = self.round(self.begin())
        for c in run.cohort:
            run.controllers[c].check()
            run.submit(c, 'scope-prepare')
        original = self.api.snapshot
        def hanging(runner, task, **kwargs):
            result = original(runner, task, **kwargs)
            if self.api.jobs[task][1]['role'] == 'scope-cleanup':
                result.update(state='running', stop_confirmed=False)
            return result
        self.api.snapshot = hanging
        self.assertFalse(run.teardown())
        maintenance = {j['descriptor']['task_id'] for j in run.phase_state()['jobs'].values() if j['descriptor']['role'] == 'scope-cleanup'}
        self.assertTrue(maintenance)
        self.assertTrue(maintenance.issubset({e[3] for e in self.api.events if e[0] == 'stop'}))
        self.assertFalse(run.phase_state()['cleanup_confirmed'])
        self.assertLessEqual(self.clock.now, 280)
    def test_active_empty_check_owner_allows_immediate_stop_and_blocks_second_start(self):
        entered, release = threading.Event(), threading.Event()
        original = self.api.check
        def blocked(*args, **kwargs):
            entered.set()
            release.wait(3)
            return original(*args, **kwargs)
        self.api.check = blocked
        args = ['--config', str(self.config), '--state-dir', str(self.store.root)]
        outcome = []
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            worker = threading.Thread(target=lambda: outcome.append(demo.main(['before'] + args, api=self.api)))
            worker.start()
            self.assertTrue(entered.wait(2))
            started = time.monotonic()
            self.assertEqual(2, demo.main(['before'] + args, api=self.api))
            self.assertEqual(2, demo.main(['stop'] + args, api=self.api))
            self.assertLess(time.monotonic() - started, 1)
            release.set()
            worker.join(3)
        self.assertFalse(worker.is_alive())
        self.assertEqual([2], outcome)
        self.assertEqual([], self.api.events)
    def test_symlink_locks_are_refused_without_touching_external_file(self):
        sentinel = self.root / 'external'
        sentinel.write_text('retain-external')
        sentinel.chmod(0o600)
        for name in ('metadata', 'phase-owner'):
            path = self.store.root / (name + '.lock')
            path.unlink(missing_ok=True)
            path.symlink_to(sentinel)
            with self.assertRaises(CaseError):
                with self.store.lock(name, blocking=False): pass
            self.assertEqual('retain-external', sentinel.read_text())
            path.unlink()
    def test_session_directory_latest_and_json_symlinks_are_refused(self):
        directory = self.begin()
        for path in (self.store.root / 'latest.json', directory / 'session.json'):
            backup = self.root / ('external-' + path.name)
            path.rename(backup)
            path.symlink_to(backup)
            with self.assertRaises(CaseError):
                self.store.latest() if path.name == 'latest.json' else self.store.read(directory)
            path.unlink()
            backup.rename(path)
        backup = self.root / 'external-session'
        directory.rename(backup)
        directory.symlink_to(backup, target_is_directory=True)
        with self.assertRaises(CaseError): self.store.latest()
    def test_insecure_permissions_owner_and_nested_role_link_are_refused(self):
        directory = self.begin()
        path = directory / 'session.json'
        path.chmod(0o644)
        with self.assertRaises(CaseError): self.store.read(directory)
        path.chmod(0o600)
        with patch.object(demo.os, 'getuid', return_value=demo.os.getuid() + 1):
            with self.assertRaises(CaseError): self.store.read(directory)
        role = directory / 'unsafe-role'
        role.symlink_to(self.config)
        with self.assertRaises(CaseError): self.round(directory)
        role.unlink()
        self.store.root.chmod(0o755)
        with self.assertRaises(CaseError): demo.Store(self.store.root)
    def test_missing_retained_baseline_rejects_after_before_any_new_start(self):
        run = self.round(self.begin())
        run.run()
        run.controllers['client-a'].path('client-a', 'before', 'baseline').unlink()
        count = len(self.api.events)
        with self.assertRaises(CaseError): self.begin('after')
        self.assertEqual(count, len(self.api.events))
    def failed_cleanup_round(self):
        run = self.round(self.begin())
        for client in run.cohort:
            run.controllers[client].check()
            run.submit(client, 'scope-prepare')
        self.api.cleanup_reject = True
        self.assertFalse(run.teardown())
        run.change(status='Recovery required')
        return run
    def test_explicit_stop_retries_terminal_failed_cleanup_with_history(self):
        run = self.failed_cleanup_round()
        old_key = run.phase_state()['cleanup_current']['client-a']
        old_job = copy.deepcopy(run.phase_state()['jobs'][old_key])
        self.api.cleanup_reject = False
        args = ['stop', '--config', str(self.config), '--state-dir', str(self.store.root)]
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(0, demo.main(args, api=self.api))
        phase = run.phase_state()
        self.assertEqual('Failed', phase['status'])
        new_key = phase['cleanup_current']['client-a']
        self.assertNotEqual(old_key, new_key)
        self.assertNotEqual(old_job['descriptor']['task_id'], phase['jobs'][new_key]['descriptor']['task_id'])
        self.assertNotEqual(old_job['descriptor']['controller_id'], phase['jobs'][new_key]['descriptor']['controller_id'])
        self.assertEqual(old_job['descriptor'], phase['jobs'][old_key]['descriptor'])
        self.assertEqual(2, phase['jobs'][old_key]['cleanup_result']['exit_code'])
        self.assertTrue(phase['cleanup_confirmed'])
    def test_concurrent_stops_share_one_cleanup_retry_cas(self):
        run = self.failed_cleanup_round()
        candidates = demo.cleanup_retries(run.phase_state())
        self.api.cleanup_reject = False
        barrier = threading.Barrier(2)
        outcomes = []
        def recover():
            other = self.round(run.directory)
            barrier.wait()
            outcomes.append(other.teardown(retry_candidates=candidates))
        workers = [threading.Thread(target=recover) for _ in range(2)]
        for worker in workers: worker.start()
        for worker in workers: worker.join(3)
        self.assertFalse(any(worker.is_alive() for worker in workers))
        self.assertEqual([True, True], sorted(outcomes))
        retries = [j for j in run.phase_state()['jobs'].values() if j.get('retry_of')]
        self.assertEqual(1, len(retries))
    def test_unknown_or_active_cleanup_never_gets_new_attempt(self):
        run = self.failed_cleanup_round()
        old = run.job('client-a', 'scope-cleanup')['descriptor']['task_id']
        candidates = demo.cleanup_retries(run.phase_state())
        self.api.unknown.add(old)
        self.assertFalse(run.teardown(retry_candidates=candidates))
        self.assertFalse(any(j.get('retry_of') for j in run.phase_state()['jobs'].values()))
        self.api.unknown.clear()
        original = self.api.snapshot
        def active(runner, task, **kwargs):
            result = original(runner, task, **kwargs)
            if task == old: result.update(state='running', stop_confirmed=False)
            return result
        self.api.snapshot = active
        self.assertFalse(run.teardown(retry_candidates=candidates))
        self.assertFalse(any(j.get('retry_of') for j in run.phase_state()['jobs'].values()))
    def test_explicit_stop_retries_at_most_once_per_scope(self):
        run = self.failed_cleanup_round()
        self.assertFalse(run.teardown(retry_candidates=demo.cleanup_retries(run.phase_state())))
        self.assertEqual(1, sum(bool(j.get('retry_of')) for j in run.phase_state()['jobs'].values()))
    def test_safe_runner_refusal_preserves_reason_and_recovery_identity(self):
        run = self.round(self.begin())
        self.api.RunnerError = REAL.RunnerError
        original = self.api.start
        def refusal(*args, **kwargs):
            original(*args, **kwargs)
            raise REAL.ValidationError('workload must use the installed release entry')
        self.api.start = refusal
        output = []
        run.output = output.append
        with self.assertRaisesRegex(CaseError, 'installed release entry'):
            run.run()
        self.assertIn('installed release entry', run.phase_state()['failure'])
        topic = run.job('client-a', 'topic')['descriptor']
        text = '\n'.join(output)
        self.assertIn(topic['task_id'], text)
        self.assertIn(topic['controller_id'], text)
        self.assertIn(str(HERE / 'demo'), text)
    def test_arbitrary_transport_error_details_remain_hidden(self):
        run = self.round(self.begin())
        original = self.api.start
        def refusal(*args, **kwargs):
            original(*args, **kwargs)
            raise OSError('private diagnostic must stay hidden')
        self.api.start = refusal
        with self.assertRaises(CaseError): run.run()
        self.assertNotIn('private diagnostic', run.phase_state()['failure'])
    def test_private_atomic_session_files(self):
        self.begin()
        for path in self.store.root.rglob('*'):
            self.assertEqual(0o700 if path.is_dir() else 0o600, path.stat().st_mode & 0o777)


if __name__ == '__main__': unittest.main()
