"""Local, single-round orchestration. Remote execution stays on runner wire v1."""
import argparse
import concurrent.futures
import contextlib
import copy
import fcntl
import json
import os
import pathlib
import shlex
import stat
import sys
import time
import uuid
from types import SimpleNamespace

from .cli import Controller, phase_run_id, runner_api, task_id
from .config import CaseError, fingerprint, load, topology
from .presenter import DisplayError, Presenter
from .view import Freshness, observation, ready_barrier

TERMINAL = ("Succeeded", "Failed")


def private_info(info, directory=False):
    kind = stat.S_ISDIR if directory else stat.S_ISREG
    expected = 0o700 if directory else 0o600
    if not kind(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != expected:
        raise CaseError('State must be owned by this user with directory 0700 / file 0600 permissions')


def private_dir(path):
    path = pathlib.Path(path).absolute()
    if path.is_symlink():
        raise CaseError('State directory must not be a symlink')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    private_info(path.lstat(), directory=True)
    return path.resolve()


def read_private(path):
    try:
        fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        raise CaseError('State file must be a private regular file without symlinks') from None
    with os.fdopen(fd) as stream:
        private_info(os.fstat(stream.fileno()))
        return json.load(stream)


def validate_tree(directory):
    private_info(directory.lstat(), directory=True)
    for path in directory.rglob('*'):
        try:
            info = path.lstat()
        except FileNotFoundError:
            # Another local controller may have just atomically published and
            # removed its private temporary file. Required files are opened
            # separately with no-follow checks before use.
            continue
        if stat.S_ISLNK(info.st_mode):
            raise CaseError('State must not contain symlinks')
        private_info(info, directory=stat.S_ISDIR(info.st_mode))


def atomic(path, value):
    private_info(path.parent.lstat(), directory=True)
    if path.exists() or path.is_symlink():
        if path.is_symlink():
            raise CaseError('State file must not be a symlink')
        private_info(path.lstat())
    temporary = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    fd = os.open(str(temporary), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(str(temporary), str(path))
        directory = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        temporary.unlink(missing_ok=True)


class Store:
    def __init__(self, root):
        self.root = private_dir(root)

    @contextlib.contextmanager
    def lock(self, name='metadata', blocking=True):
        try:
            fd = os.open(str(self.root / (name + '.lock')), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        except OSError:
            raise CaseError('State lock must be a private regular file without symlinks') from None
        try:
            private_info(os.fstat(fd))
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
            except BlockingIOError:
                raise CaseError("A demo phase owns this state. Use demo status/stop with this state directory") from None
            yield
        finally:
            os.close(fd)

    def latest(self):
        pointer = self.root / 'latest.json'
        if not pointer.exists() and not pointer.is_symlink():
            raise CaseError('No demo session. Run before first')
        name = read_private(pointer)['session_id']
        if not name.startswith('demo-') or pathlib.Path(name).name != name:
            raise CaseError('Invalid session pointer; retain state for recovery')
        directory = self.root / name
        self.bounded(directory)
        return directory

    def bounded(self, directory):
        if directory.parent != self.root or directory.is_symlink():
            raise CaseError('Session directory must remain within the private state root')
        private_info(directory.lstat(), directory=True)

    def read(self, directory):
        self.bounded(directory)
        return read_private(directory / 'session.json')

    def update(self, directory, mutate):
        with self.lock():
            state = self.read(directory)
            mutate(state)
            atomic(directory / 'session.json', state)
            return state


def inputs(config, clients, api):
    case = load(config)
    selected = clients.split(',') if clients else list(case['clients'])
    if not selected or len(set(selected)) != len(selected) or any(c not in case['clients'] for c in selected):
        raise CaseError('Invalid selected cohort')
    case['clients'] = {c: case['clients'][c] for c in selected}
    runners = {c: api.load_runner(case['clients'][c]['runner_file']).as_dict() for c in selected}
    return case, selected, runners, fingerprint({'case': case, 'runners': runners})


def failed_cleanup(job):
    result = job.get('cleanup_result') or job.get('stop_result') or {}
    return (job.get('stop_confirmed') and not job.get('cleanup_confirmed')
            and result.get('stop_confirmed') and result.get('state') in ('stopped', 'failed')
            and (result.get('state') == 'failed' or isinstance(result.get('exit_code'), int) and result['exit_code'] != 0))


def cleanup_retries(phase):
    candidates = {}
    for client, key in phase.get('cleanup_current', {}).items():
        if failed_cleanup(phase['jobs'][key]):
            candidates[client] = key
    return candidates


class DemoController(Controller):
    """Reuse case behavior with durable, private local evidence writes."""
    def write(self, path, value):
        if path.exists() or path.is_symlink():
            raise CaseError('Refusing to overwrite immutable role/evidence state')
        atomic(path, value)

    def notice(self, message):
        # Round's customer stages already describe the same local operation.
        pass


class Round:
    """One owner; injected API/clock make lifecycle behavior locally testable."""
    def __init__(self, store, directory, phase, api, clock=time.monotonic, sleep=time.sleep, output=print, lang='en', details=False):
        self.store, self.directory, self.phase, self.api = store, directory, phase, api
        self.clock, self.sleep, self.output = clock, sleep, output
        self.presenter = Presenter(lambda value: self.output(value), lang, details, sys.stdout if output is print else None, clock)
        self.state = store.read(directory)
        validate_tree(directory)
        self.case = self.state['case']
        self.cohort = self.state['cohort']
        self.deadline = clock() + 900
        self.request_deadline = self.deadline
        self.freshness = Freshness(clock=clock)
        self.sample_cache = {}
        self.controllers = {}
        for client in self.cohort:
            expected_runner = directory / (client + '-runner.json')
            if self.case['clients'][client]['runner_file'] != str(expected_runner):
                raise CaseError('Frozen runner path differs from this private session')
            if read_private(expected_runner) != self.state['runners'][client]:
                raise CaseError('Frozen runner snapshot differs from session target')
            args = SimpleNamespace(client=client, phase=phase, cohort=','.join(self.cohort), state_dir=str(directory / 'roles'), config=str(directory / 'case.json'), json=False)
            controller = DemoController(self.case, args, api)
            controller.clock = clock
            controller.read = lambda client, phase, role, controller=controller: read_private(controller.path(client, phase, role))
            # Route role-plan prerequisite reads through this round's deadline
            # and freshness tracking; manual Controller behavior is unchanged.
            controller.snapshot = lambda client, phase, role, renew=False: self.sample_one(self.job(client, role), renew)
            self.controllers[client] = controller

    def read(self):
        return self.store.read(self.directory)

    def phase_state(self):
        return self.read()['phases'][self.phase]

    def change(self, **values):
        self.store.update(self.directory, lambda s: s['phases'][self.phase].update(values))

    def job(self, client, role):
        phase = self.phase_state()
        key = phase.get('cleanup_current', {}).get(client, client + '/' + role) if role == 'scope-cleanup' else client + '/' + role
        return phase['jobs'][key]

    def guard(self):
        if self.clock() >= self.deadline:
            raise CaseError('Phase execution deadline reached')
        if self.phase_state()['stop_requested']:
            raise CaseError('Stop requested')

    def sample_one(self, job, renew=False):
        descriptor = job['descriptor']
        result = self.api.snapshot(job['runner'], descriptor['task_id'], controller_id=descriptor['controller_id'] if renew else None, renew=renew, deadline=min(self.deadline, self.request_deadline))
        result['task_id'] = descriptor['task_id']
        result['frame_age_ms'] = self.freshness.age(result) * 1000
        result['_case_received_mono'] = self.clock()
        return result

    def sample(self, renew=True):
        jobs = self.phase_state()['jobs']
        # Terminal helper/final envelopes are immutable on wire v1; do not
        # spend live polling capacity renewing already stopped tasks. A fresh
        # status invocation starts with an empty cache and queries each target.
        sampled = {key: self.sample_cache[key] for key in jobs if key in self.sample_cache}
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as workers:
            futures = {key: workers.submit(self.sample_one, job, renew) for key, job in jobs.items() if key not in sampled}
            for key, future in futures.items():
                sampled[key] = future.result()
                if sampled[key].get('stop_confirmed') and sampled[key].get('state') in ('stopped', 'failed'):
                    self.sample_cache[key] = sampled[key]
        return sampled

    def aged(self, snapshot):
        result = dict(snapshot)
        if result.get('frame_age_ms') is not None:
            result['frame_age_ms'] += max(0, self.clock() - result['_case_received_mono']) * 1000
        return result

    def submit(self, client, role, maintenance=False, retry_from=None):
        self.request_deadline = self.deadline
        controller = self.controllers[client]
        if role == 'topic':
            argv = ['./workload', 'topic', 'create', '--config', self.case['clients'][client]['remote_connection_file'], '--topic', self.case['topic'], '--partitions', str(self.case['workload']['partitions'])]
            scope = None
        else:
            argv, scope = controller.role_plan(role, verify_barrier=False)
        descriptor = {'schema_version': 1, 'task_id': task_id(self.case, client, self.phase, role), 'controller_id': uuid.uuid4().hex, 'role': role, 'run_id': self.case['run_id'], 'phase': self.phase, 'argv': argv}
        if scope:
            descriptor['scope_id'] = scope
        key = client + '/' + role
        # The claim, stop intent, descriptor and attempt share one short lock.
        # No network request holds it; status/stop remain independently usable.
        with self.store.lock():
            state = self.read()
            phase = state['phases'][self.phase]
            if role == 'scope-cleanup':
                current = phase.setdefault('cleanup_current', {}).get(client, key)
                if retry_from is not None:
                    if current != retry_from:
                        return phase['jobs'][current]
                    if not maintenance or not failed_cleanup(phase['jobs'][current]):
                        raise CaseError('Cleanup retry requires the original attempt confirmed stopped and terminal failed')
                    key = client + '/scope-cleanup-retry-' + uuid.uuid4().hex[:12]
                    descriptor['task_id'] += '-r' + uuid.uuid4().hex[:8]
                    descriptor['controller_id'] = uuid.uuid4().hex
                elif current in phase['jobs']:
                    return phase['jobs'][current]
            elif key in phase['jobs']:
                return phase['jobs'][key]
            if self.clock() >= self.deadline or (phase['stop_requested'] and not maintenance):
                raise CaseError('Stop requested or deadline reached; start refused')
            if maintenance and any(not j.get('stop_confirmed') for j in phase['jobs'].values() if j['descriptor']['role'] != 'scope-cleanup'):
                raise CaseError('Scope cleanup requires every owned mutable task stopped')
            job = {'client': client, 'runner': state['runners'][client], 'descriptor': descriptor, 'attempt': 'submitting', 'stop_confirmed': False}
            if retry_from is not None:
                job['retry_of'] = retry_from
            controller.write(controller.root / (descriptor['task_id'] + '.json'), descriptor)
            phase['jobs'][key] = job
            if role == 'scope-cleanup':
                phase['cleanup_current'][client] = key
            atomic(self.directory / 'session.json', state)
        # An exception or killed owner here leaves submitting, never not-started.
        result = self.api.start(job['runner'], descriptor, deadline=self.deadline)
        def acknowledged(state):
            saved = state['phases'][self.phase]['jobs'][key]
            saved['attempt'] = 'acknowledged'
            saved['start_result'] = result
        self.store.update(self.directory, acknowledged)
        return job

    def is_fresh(self, snapshot):
        if snapshot.get("frame_age_ms") is None:
            return False
        return self.aged(snapshot)["frame_age_ms"] <= 15000

    def show(self, sampled):
        items = []
        for client in self.cohort:
            snapshot = sampled.get(client + '/watch')
            if not snapshot or not snapshot.get('last_frame'):
                continue
            snapshot = self.aged(snapshot)
            frame = copy.deepcopy(snapshot['last_frame'])
            frame['task_id'] = snapshot['task_id']
            frame['identity'] = snapshot.get('identity', {})
            frame['role_states'] = {role: sampled.get(client + '/' + role, {}).get('state', 'not-started') for role in ('watch', 'consume', 'produce')}
            frame['warmup_seconds'] = self.case['observation']['warmup_seconds']
            workload = dict(frame.get('workload', {}))
            workload['frames_fresh'] = workload.get('frames_fresh', False) and all(self.is_fresh(sampled.get(client + '/' + role, {})) for role in ('consume', 'produce'))
            baseline = None
            if self.phase == 'after':
                baseline = read_private(self.controllers[client].path(client, 'before', 'baseline'))
                if frame.get('retained_window') and all(c + '/' + r in sampled for c in self.cohort for r in ('produce', 'consume')):
                    self.controllers[client].evidence(frame['retained_window'], self.evidence_samples(sampled))
            items.append({'frame': frame, 'age': snapshot['frame_age_ms'] / 1000, 'workload': workload, 'baseline': baseline,
                          'producer': (sampled.get(client + '/produce', {}).get('last_frame') or {}),
                          'consumer': (sampled.get(client + '/consume', {}).get('last_frame') or {})})
        self.presenter.live(items)

    def final_summary(self, sampled=None):
        phase = self.phase_state()
        items = []
        for client, controller in self.controllers.items():
            item = {'client': client, 'saved': False}
            for role, label in (('produce', 'producer'), ('consume', 'consumer')):
                job = phase['jobs'].get(client + '/' + role, {})
                snapshot = (sampled or {}).get(client + '/' + role) or job.get('stop_result') or {}
                item[label] = snapshot.get('last_frame') or {}
            path = controller.path(client, self.phase, 'baseline' if self.phase == 'before' else 'result')
            if path.exists():
                frame = read_private(path)
                item.update(saved=True, frame=frame, age=frame.get('capture_frame_age_ms', float('inf')) / 1000, workload=frame.get('workload', {}))
                if self.phase == 'after':
                    item['baseline'] = read_private(controller.path(client, 'before', 'baseline'))
            items.append(item)
        entry = str(pathlib.Path(__file__).resolve().parent.parent / 'demo')
        after = shlex.join([entry, 'after', '--config', self.state['template_path'], '--state-dir', str(self.store.root), '--lang', self.presenter.lang])
        verified = None if sampled is None else all(s.get('stop_confirmed') and s.get('state') in ('stopped', 'failed') for s in sampled.values())
        candidate, complete = topology(self.case)['zone_cidr'], False
        try:
            template = load(self.state['template_path'])
            _, _, runners, source = inputs(self.state['template_path'], ','.join(self.cohort), self.api)
            selected = copy.deepcopy(template)
            selected['clients'] = {c: selected['clients'][c] for c in self.cohort}
            # Both reads must describe the same selected inputs, including the
            # normalized runner paths and current target. Never mutate state.
            if source == self.state['input_fingerprint'] == fingerprint({'case': selected, 'runners': runners}):
                candidate, complete = topology(template)['zone_cidr'], True
        except Exception:
            # Status/recovery must keep working with the frozen target even
            # after the original template was edited, removed or malformed.
            pass
        self.presenter.final(self.phase, phase, items, candidate, after, verified, complete)

    def evidence_samples(self, sampled):
        return {(client, role): self.aged(sampled[client + '/' + role]) for client in self.cohort for role in ('produce', 'consume')}

    def wait(self, predicate, budget, label):
        until = min(self.deadline, self.clock() + budget)
        self.presenter.stage(label)
        self.request_deadline = until
        while True:
            self.guard()
            sampled = self.sample()
            self.guard()
            self.show(sampled)
            if predicate(sampled):
                return sampled
            if self.clock() >= until:
                raise CaseError(label + ' timed out')
            self.sleep(min(3, max(0, until - self.clock())))

    def finished(self, snapshot):
        if snapshot.get('state') not in ('stopped', 'failed') or not snapshot.get('stop_confirmed'):
            return False
        if snapshot.get('exit_code') != 0:
            raise CaseError('Owned task failed: ' + snapshot['task_id'])
        return True

    def run(self):
        failure = None
        success = False
        try:
            self.presenter.start(self.phase, self.case, self.cohort)
            self.presenter.stage('check')
            setup = min(self.deadline, self.clock() + 300)
            for client, controller in self.controllers.items():
                self.guard()
                # Controller.check writes only local evidence; adapter supplies deadline.
                original = controller.api
                class Checked:
                    def check(inner, runner, requirements):
                        return self.api.check(runner, requirements, deadline=min(self.deadline, setup))
                controller.api = Checked()
                try:
                    result = controller.check()
                finally:
                    controller.api = original
                if not result.get('ok') or not controller.spec()['identity_verified']:
                    raise CaseError('Client check failed: ' + client)
            self.submit(self.cohort[0], 'topic')
            self.wait(lambda s: self.finished(s[self.cohort[0] + '/topic']), max(0, setup - self.clock()), 'Preparing topic')
            for client in self.cohort:
                self.submit(client, 'scope-prepare')
            self.wait(lambda s: all(self.finished(s[c + '/scope-prepare']) for c in self.cohort), max(0, setup - self.clock()), 'Preparing owned scopes and source proof')
            for client in self.cohort:
                self.submit(client, 'watch')
            def capture(sampled):
                for client in self.cohort:
                    snap = self.aged(sampled[client + '/watch'])
                    frame = snap.get('last_frame') or {}
                    quality = frame.get('quality', {})
                    if snap.get('state') not in ('ready', 'running') or snap.get('frame_age_ms', float('inf')) > 15000 or not quality.get('complete') or not quality.get('source_verified') or not quality.get('scope_intact'):
                        return False
                return True
            self.wait(capture, 120, 'Waiting for all capture frames')
            for client in self.cohort:
                self.submit(client, 'consume')
            def ready(sampled):
                return not ready_barrier({c: self.aged(sampled[c + '/consume']) for c in self.cohort}, self.case['workload']['partitions'], self.case['topic'], phase_run_id(self.case, self.phase))
            self.wait(ready, 120, 'Waiting for every consumer current-end barrier')
            # Recheck all consumers immediately before every producer submission.
            for client in self.cohort:
                self.wait(ready, 30, 'Checking cohort ready barrier')
                self.submit(client, 'produce')
            self.change(status='Running')
            self.wait(lambda s: all(self.finished(s[c + '/produce']) for c in self.cohort), 300, 'Running producers')
            self.change(status='Draining')
            def drained(sampled):
                evidence = self.controllers[self.cohort[0]].evidence({}, self.evidence_samples(sampled))
                if evidence.get('offset_issue') and 'consumer progress stale' not in evidence['offset_issue']:
                    raise CaseError(evidence['offset_issue'])
                return evidence.get('drained', False)
            sampled = self.wait(drained, 180, 'Draining every consumer to cohort final ACK+1')
            for client, controller in self.controllers.items():
                self.guard()
                watch = self.aged(sampled[client + '/watch'])
                retained = copy.deepcopy((watch.get('last_frame') or {}).get('retained_window'))
                if watch.get('frame_age_ms', float('inf')) > 15000 or not retained:
                    raise CaseError('No fresh retained business window: ' + client)
                state, _ = observation(retained, retained.get('capture_frame_age_ms', float('inf')) / 1000, retained.get('workload', {}), self.case['observation']['warmup_seconds'])
                if state != 'observing':
                    raise CaseError('Retained window is incomplete: ' + client)
                evidence = controller.evidence(retained, self.evidence_samples(sampled))
                if not evidence['drained']:
                    raise CaseError('Final drain evidence incomplete')
                controller.write(controller.path(client, self.phase, 'baseline' if self.phase == 'before' else 'result'), evidence)
            success = True
        except (Exception, KeyboardInterrupt) as error:
            failure = str(error) if isinstance(error, (CaseError, DisplayError, getattr(self.api, 'RunnerError', CaseError))) else 'Interrupted' if isinstance(error, KeyboardInterrupt) else 'Operation failed; retained task identities require status/stop'
            self.change(failure=failure)
        finally:
            clean = self.teardown()
            self.change(status='Succeeded' if success and clean else 'Failed' if clean else 'Recovery required')
        self.final_summary()
        if not success or not clean:
            self.recovery()
            raise CaseError(failure or 'Cleanup unconfirmed')

    def teardown(self, retry_candidates=None):
        retry_candidates = retry_candidates or {}
        retried = set()
        finish_deadline = self.clock() + 180
        # Reserve the last 30 seconds to stop an unfinished maintenance task.
        self.deadline = finish_deadline - 30
        self.request_deadline = self.deadline
        self.change(status='Stopping', stop_requested=True)
        self.presenter.stage('Stopping', best_effort=True)
        try:
            jobs = self.phase_state()['jobs']
            def stop_one(item):
                key, job = item
                descriptor = job['descriptor']
                try:
                    result = self.api.stop(job['runner'], descriptor['task_id'], descriptor['controller_id'], deadline=self.deadline)
                except Exception:
                    result = {'state': 'disconnected', 'stop_confirmed': False}
                # A pending SSM start can arrive after a missing snapshot/stop.
                confirmed = bool(result.get('stop_confirmed')) and result.get('state') in ('stopped', 'failed')
                self.store.update(self.directory, lambda s: s['phases'][self.phase]['jobs'][key].update(stop_confirmed=confirmed, stop_result=result))
                return confirmed
            with concurrent.futures.ThreadPoolExecutor(max_workers=6) as workers:
                results = list(workers.map(stop_one, ((key, job) for key, job in jobs.items() if job['descriptor']['role'] != 'scope-cleanup')))
            if not all(results):
                return False
            self.change(status='Cleaning')
            self.presenter.stage('Cleaning', best_effort=True)
            for client in self.cohort:
                if client + '/scope-prepare' not in jobs:
                    continue
                current = self.phase_state()
                key = current.get('cleanup_current', {}).get(client, client + '/scope-cleanup')
                # Retry eligibility is frozen at explicit stop entry; CAS below
                # makes concurrent callers share one replacement attempt.
                if key not in current['jobs']:
                    self.submit(client, 'scope-cleanup', maintenance=True)
                while self.clock() < self.deadline:
                    current = self.phase_state()
                    key = current.get('cleanup_current', {}).get(client, client + '/scope-cleanup')
                    job = current['jobs'][key]
                    snap = self.sample_one(job, renew=True)
                    if snap.get('state') in ('stopped', 'failed') and snap.get('stop_confirmed'):
                        confirmed = snap.get('exit_code') == 0 and (snap.get('last_frame') or {}).get('result', {}).get('state') == 'cleaned'
                        self.store.update(self.directory, lambda s: s['phases'][self.phase]['jobs'][key].update(stop_confirmed=True, cleanup_confirmed=confirmed, cleanup_result=snap, stop_result=snap))
                        if not confirmed:
                            if client not in retried and retry_candidates.get(client) == key and failed_cleanup(self.phase_state()['jobs'][key]):
                                retried.add(client)
                                self.submit(client, 'scope-cleanup', maintenance=True, retry_from=key)
                                continue
                            return False
                        break
                    self.sleep(min(1, max(0, self.deadline - self.clock())))
                else:
                    return False
            self.change(cleanup_confirmed=True)
            return True
        except (Exception, KeyboardInterrupt):
            return False
        finally:
            # Cleanup is owned work too. Stopping it never proves the scope
            # was cleaned; only its successful result sets cleanup_confirmed.
            for key, job in self.phase_state()['jobs'].items():
                if job['descriptor']['role'] != 'scope-cleanup' or job.get('cleanup_confirmed'):
                    continue
                descriptor = job['descriptor']
                try:
                    stopped = self.api.stop(job['runner'], descriptor['task_id'], descriptor['controller_id'], deadline=finish_deadline)
                except (Exception, KeyboardInterrupt):
                    stopped = {'state': 'disconnected', 'stop_confirmed': False}
                confirmed = bool(stopped.get('stop_confirmed')) and stopped.get('state') in ('stopped', 'failed')
                self.store.update(self.directory, lambda state: state['phases'][self.phase]['jobs'][key].update(stop_confirmed=confirmed, stop_result=stopped))

    def recovery(self):
        entry = str(pathlib.Path(__file__).resolve().parent.parent / 'demo')
        for job in self.phase_state()['jobs'].values():
            descriptor = job['descriptor']
            self.presenter.message('Target {} | task {} | controller {} | stop-confirmed {}'.format(job['runner'], descriptor['task_id'], descriptor['controller_id'], job.get('stop_confirmed')))
        for operation in ('status', 'stop'):
            self.presenter.message(shlex.join([entry, operation, '--config', self.state['template_path'], '--state-dir', str(self.store.root)]))


def begin(store, config, clients, phase, api):
    with store.lock():
        if (store.root / 'latest.json').exists():
            directory = store.latest()
            state = store.read(directory)
            if any(p['status'] not in TERMINAL or not p.get('cleanup_confirmed') for p in state['phases'].values()):
                raise CaseError('Recovery required for latest session; run demo status/stop before another phase')
        elif phase == 'after':
            raise CaseError('Successful before baseline required')
        if phase == 'after':
            if state['phases']['before']['status'] != 'Succeeded' or 'after' in state['phases']:
                raise CaseError('Successful unused before baseline required; run a new before')
            for client in state['cohort']:
                path = directory / 'roles' / (task_id(state['case'], client, 'before', 'baseline') + '.json')
                baseline = read_private(path)
                if not baseline.get('drained') or not baseline.get('successful_messages'):
                    raise CaseError('Successful retained before baseline required for every client')
            clients = clients or ','.join(state['cohort'])
        case, cohort, runners, source = inputs(config, clients, api)
        if phase == 'before':
            session_id = 'demo-' + uuid.uuid4().hex[:20]
            directory = private_dir(store.root / session_id)
            for client in cohort:
                runner_file = directory / (client + '-runner.json')
                atomic(runner_file, runners[client])
                case['clients'][client]['runner_file'] = str(runner_file)
            case['run_id'] = session_id
            atomic(directory / 'case.json', case)
            state = {'schema_version': 1, 'session_id': session_id, 'run_id': session_id, 'created_at': time.time(), 'template_path': str(pathlib.Path(config).resolve()), 'input_fingerprint': source, 'cohort': cohort, 'case': case, 'runners': runners, 'phases': {}}
        elif source != state['input_fingerprint'] or cohort != state['cohort']:
            raise CaseError('Case, cohort or runner target changed; run a new before')
        state['phases'][phase] = {'status': 'Preparing', 'claim': uuid.uuid4().hex, 'created_at': time.time(), 'execution_deadline_at': time.time() + 900, 'deadline_seconds': 900, 'stop_requested': False, 'cleanup_confirmed': False, 'jobs': {}}
        atomic(directory / 'session.json', state)
        atomic(store.root / 'latest.json', {'session_id': state['session_id']})
        return directory


def main(argv=None, api=None):
    parser = argparse.ArgumentParser(description='Run one cross-AZ round in one local terminal. Configure CIDR manually between before and after.')
    parser.add_argument('operation', choices=('before', 'after', 'status', 'stop'))
    parser.add_argument('--config', required=True)
    parser.add_argument('--state-dir', required=True)
    parser.add_argument('--clients')
    parser.add_argument('--lang', choices=('en', 'zh'), default='en', help='customer output language (default: en)')
    parser.add_argument('--details', action='store_true', help='include technical task, capture and phase details')
    args = parser.parse_args(argv)
    try:
        api = api or runner_api()
        store = Store(args.state_dir)
        if args.operation in ('before', 'after'):
            with store.lock('phase-owner', blocking=False):
                directory = begin(store, args.config, args.clients, args.operation, api)
                Round(store, directory, args.operation, api, lang=args.lang, details=args.details).run()
        else:
            with store.lock():
                directory = store.latest()
                state = store.read(directory)
                if args.clients and args.clients.split(',') != state['cohort']:
                    raise CaseError('Clients must match the latest session cohort')
                phase = 'after' if 'after' in state['phases'] else 'before'
                if args.operation == 'stop':
                    previous = state['phases'][phase]
                    retry_candidates = cleanup_retries(previous)
                    if previous['status'] == 'Succeeded' and previous.get('cleanup_confirmed') and all(job.get('stop_confirmed') for job in previous['jobs'].values()):
                        print('本轮进程已停止，采集环境已清理，历史结果保留。' if args.lang == 'zh' else 'All round processes are stopped and capture cleanup is confirmed. History is retained.')
                        return 0
                    state['phases'][phase]['stop_requested'] = True
                    atomic(directory / 'session.json', state)
            round_ = Round(store, directory, phase, api, lang=args.lang, details=args.details)
            if args.operation == 'status':
                sampled = round_.sample(renew=False)
                if round_.phase_state()['status'] in TERMINAL:
                    round_.final_summary(sampled)
                else:
                    round_.presenter.message(round_.presenter.t('Round is active; status does not extend its runtime.', '本轮仍在执行；查询状态不会延长运行时间。'))
                    round_.show(sampled)
                if round_.phase_state()['status'] not in TERMINAL or any(not snap.get('stop_confirmed') or snap.get('state') not in ('stopped', 'failed') for snap in sampled.values()):
                    raise CaseError('Recovery required or phase active; status does not renew leases')
            else:
                clean = round_.teardown(retry_candidates=retry_candidates)
                # Never mark a still-active owner Failed: it may have an in-flight
                # start. Its finally owns finalization; repeat stop after exit.
                try:
                    with store.lock('phase-owner', blocking=False):
                        round_.change(status=('Succeeded' if state['phases'][phase]['status'] == 'Succeeded' else 'Failed') if clean else 'Recovery required')
                except CaseError:
                    clean = False
                round_.final_summary()
                if not clean:
                    raise CaseError('Recovery required; owner active or owned stop/cleanup unconfirmed')
    except (Exception, KeyboardInterrupt) as error:
        message = str(error) if isinstance(error, CaseError) else 'Operation failed; retain private state and use demo status/stop'
        prefix = '操作未完成。保留运行记录，使用 status 查询或 stop 恢复。原因：' if args.lang == 'zh' else 'Operation did not complete. Retain state and use status/stop. Reason: '
        print(prefix + message, file=sys.stderr)
        entry = str(pathlib.Path(__file__).resolve().parent.parent / 'demo')
        for operation in ('status', 'stop'):
            print(shlex.join([entry, operation, '--config', str(pathlib.Path(args.config).resolve()), '--state-dir', str(pathlib.Path(args.state_dir).resolve())]), file=sys.stderr)
        try:
            saved = Store(args.state_dir)
            state = saved.read(saved.latest())
            for phase in state['phases'].values():
                for job in phase['jobs'].values():
                    print('Target {} | task {} | controller {} | stop-confirmed {}'.format(job['runner'], job['descriptor']['task_id'], job['descriptor']['controller_id'], job.get('stop_confirmed')), file=sys.stderr)
        except Exception:
            pass
        return 2
    return 0
