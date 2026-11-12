"""Detached bounded role supervisor. Only validated JSON events leave the host."""
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time

from .schema import ValidationError
from .storage import atomic, boot_id, group_members, lock, process_identity, read_json, same_process, task_dir

MAX_LINE = 16384
MAX_LOG = 256 * 1024


def signal_owned(identity, signum, known_members=()):
    if (not identity or identity.get('pid') != identity.get('pgid') or
            not (same_process(identity) or any(m.get('pgid') == identity['pgid'] and same_process(m) for m in known_members))):
        return False
    try:
        os.killpg(identity['pgid'], signum)
        return True
    except ProcessLookupError:
        return False


def append_event(directory, frame):
    path = Path(directory) / 'events.jsonl'
    encoded = json.dumps(frame, separators=(',', ':'), allow_nan=False).encode() + b'\n'
    if path.exists() and path.stat().st_size + len(encoded) > MAX_LOG:
        # Keep a bounded tail of complete, already sanitized JSON events.
        previous = path.read_bytes()[-MAX_LOG // 2:]
        previous = previous.split(b'\n', 1)[-1]
        temporary = Path(directory) / '.events-tail'
        fd = os.open(str(temporary), os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(previous)
        os.replace(temporary, path)
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'ab') as stream:
        stream.write(encoded)


def accept_frame(directory, state, line, now):
    try:
        frame = json.loads(line, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
        if not isinstance(frame, dict) or frame.get('schema_version') != 1 or frame.get('event') not in ('ready', 'progress', 'final', 'network', 'scope'):
            raise ValueError()
        if state['role'] in ('produce', 'consume', 'topic') and frame.get('role') != state['role']:
            raise ValueError()
        sequence = frame.get('sample_seq', state['frame_seq'] + 1)
        if type(sequence) is not int or sequence <= state['frame_seq']:
            return False
        state.update(frame_seq=sequence, frame_mono=now, last_frame=frame)
        if frame.get('event') == 'ready':
            state['ready_frame'] = frame
        if frame.get('event') == 'final':
            state['application_exit_code'] = frame.get('exit_code')
        if state['state'] != 'stopping':
            state['state'] = 'ready' if frame.get('event') == 'ready' else 'running'
        atomic(Path(directory) / 'metrics.json', frame)  # raw latest trusted event; mtime only changes with a NEW frame
        append_event(directory, frame)
        return True
    except (ValueError, TypeError, OverflowError):
        state['invalid_event_count'] = state.get('invalid_event_count', 0) + 1
        return False


def _enable_subreaper():
    if sys.platform != 'linux':
        return False  # macOS process fixtures only; remote preflight requires Linux.
    import ctypes
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        raise OSError('cannot establish the role descendant reaper')
    return True


def _adopted_children_remain():
    # Called only AFTER Popen.poll has reaped the actual role, so waitpid(-1)
    # cannot steal that role's exit status. ECHILD is a kernel-backed barrier:
    # a still-running descendant cannot fork past a parent/reparenting race.
    while True:
        try:
            pid, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return False
        if pid == 0:
            return True


def role_anchor(root, task_id):
    """Keep a verifiable group leader alive until all role descendants exit.

    No business process starts before the supervisor persists the unique anchor
    identity and writes its launch handshake. TERM does not remove the anchor;
    the supervisor can therefore still validate and kill the entire group after
    the grace period, including children forked just before their parent exits.
    """
    directory = task_dir(root, task_id)
    subreaper = _enable_subreaper()
    stopping = [False]
    def requested(_signum, _frame):
        stopping[0] = True
    signal.signal(signal.SIGTERM, requested)
    signal.signal(signal.SIGINT, requested)
    deadline = time.monotonic() + 10
    launch_path = directory / 'launch.json'
    while not launch_path.exists():
        if stopping[0] or time.monotonic() >= deadline:
            return 2
        time.sleep(0.01)
    launch = read_json(launch_path)
    if launch.get('pid') != os.getpid() or launch.get('pgid') != os.getpgrp():
        return 2
    state = read_json(directory / 'state.json')
    if stopping[0]:
        return 143
    # The argv has already passed trusted_argv in this pinned release. argv is
    # private state; no command string is evaluated here.
    try:
        child = subprocess.Popen(state['argv'], stdin=subprocess.DEVNULL, close_fds=True)
    except OSError:
        atomic(directory / 'role_exit.json', {'os_returncode': 2, 'exit_code': 2, 'descendants_remaining': False})
        return 2
    actual_identity = process_identity(child.pid) or {'pid': child.pid, 'pgid': os.getpgrp(), 'pid_start_ticks': None}
    atomic(directory / 'role_process.json', actual_identity)
    recorded = False
    while True:
        code = child.poll()
        if code is not None:
            try:
                descendants = _adopted_children_remain() if subreaper else any(member['pid'] != os.getpid() for member in group_members(os.getpgrp()))
            except OSError:
                # A failed observation cannot establish group emptiness. Keep
                # the verifiable anchor alive for supervisor TERM/KILL.
                time.sleep(0.05)
                continue
            if not recorded:
                atomic(directory / 'role_exit.json', {
                    'os_returncode': code, 'exit_code': code if code >= 0 else 128 - code,
                    'role_pid': child.pid, 'descendants_remaining': bool(descendants)})
                recorded = True
            if not descendants:
                return code if code >= 0 else 128 - code
        time.sleep(0.05)


def supervise(root, task_id):
    from .remote_agent import trusted_argv
    directory = task_dir(root, task_id)
    process = None
    state = None
    selector = selectors.DefaultSelector()
    try:
        with lock(directory):
            descriptor = read_json(directory / 'descriptor.json')
            state = read_json(directory / 'state.json')
            if state['state'] != 'starting' or state['boot_id'] != boot_id():
                return
            state['supervisor'] = process_identity(os.getpid())
            release = Path(state['release'])
            argv = trusted_argv(Path(root), release, descriptor)
            env = dict(os.environ, PYTHONPATH=str(release), PYTHONDONTWRITEBYTECODE='1',
                       WORKLOAD_JAR=str(release / 'workload.jar'))
            env.pop('PYTHONHOME', None)
            process = subprocess.Popen([sys.executable, '-m', 'runner.remote_agent', '_role', '--root', str(root), '--task-id', task_id], cwd=str(release), env=env, stdin=subprocess.DEVNULL,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       close_fds=True, start_new_session=True)
            identity = process_identity(process.pid)
            if not identity or identity['pid'] != identity['pgid']:
                process.kill()
                process.wait(timeout=2)
                raise ValidationError('child identity could not be established')
            state['anchor'] = identity
            state.update(pid=None, pgid=identity['pgid'], pid_start_ticks=None)
            state['argv'] = argv
            state['state'] = 'running'
            atomic(directory / 'state.json', state)
            atomic(directory / 'launch.json', identity)
        for stream, name in ((process.stdout, 'stdout'), (process.stderr, 'stderr')):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, selectors.EVENT_READ, name)
        pending = b''
        dropping_line = False
        stop_started = None
        forced = False
        known_members = [identity]
        while True:
            now = time.monotonic()
            with lock(directory):
                lease = read_json(directory / 'lease.json')
                stop_path = directory / 'stop.json'
                reason = None
                role_process_path = directory / 'role_process.json'
                if role_process_path.exists():
                    state.update(read_json(role_process_path))
                role_exit_path = directory / 'role_exit.json'
                if role_exit_path.exists() and read_json(role_exit_path).get('descendants_remaining'):
                    reason = 'descendants_remaining'
                if stop_path.exists():
                    request = read_json(stop_path)
                    if request.get('controller_id') == descriptor['controller_id']:
                        reason = 'requested_stop'
                if now >= state['started_mono'] + descriptor['max_runtime_seconds']:
                    reason = 'max_runtime_expired'
                elif now >= lease['deadline']:
                    reason = 'lease_expired'
                if reason and stop_started is None:
                    # Capture descendants while the unique leader identity is
                    # still valid, so an early leader exit does not orphan them.
                    if same_process(identity):
                        known_members = group_members(identity['pgid']) or [identity]
                    stop_started = now
                    state.update(state='stopping', stop_reason=reason)
                    if not signal_owned(identity, signal.SIGTERM, known_members):
                        state['stop_reason'] = 'process_identity_lost'
                if stop_started is not None and now - stop_started >= 10:
                    forced = True
                    signal_owned(identity, signal.SIGKILL, known_members)
                atomic(directory / 'state.json', state)
            # Drain a bounded chunk from each pipe every tick. stderr is never
            # persisted raw: Java/tool errors may contain credentials.
            for key, _mask in selector.select(timeout=0.1):
                try:
                    data = os.read(key.fileobj.fileno(), 65536)
                except BlockingIOError:
                    continue
                if not data:
                    selector.unregister(key.fileobj)
                    continue
                if key.data == 'stderr':
                    state['stderr_bytes_discarded'] = state.get('stderr_bytes_discarded', 0) + len(data)
                    state['stderr_tail'] = ['Remote diagnostics were suppressed; inspect safe event error codes and dependency checks.']
                    continue
                for piece in data.splitlines(keepends=True):
                    if dropping_line:
                        if piece.endswith(b'\n'):
                            dropping_line = False
                        continue
                    pending += piece
                    if len(pending) > MAX_LINE:
                        state['invalid_event_count'] = state.get('invalid_event_count', 0) + 1
                        dropping_line = not pending.endswith(b'\n')
                        pending = b''
                    elif pending.endswith(b'\n'):
                        accept_frame(directory, state, pending, time.monotonic())
                        pending = b''
            code = process.poll()
            if code is not None and not selector.get_map():
                if not group_members(identity['pgid']):
                    break
                if stop_started is None:
                    stop_started = time.monotonic()
                    state.update(state='stopping', stop_reason='descendants_remaining')
                    # If no member was observed while the leader was valid,
                    # report unconfirmed rather than signal an unverified group.
                    signal_owned(identity, signal.SIGTERM, known_members)
            if forced and stop_started is not None and time.monotonic() - stop_started > 12:
                break  # never wait indefinitely on an unkillable process
        anchor_code = process.poll()
        role_exit = read_json(directory / 'role_exit.json') if (directory / 'role_exit.json').exists() else {}
        raw_code = anchor_code if forced else role_exit.get('os_returncode', anchor_code)
        # A direct child was reaped (or remains visibly unconfirmed). Verify its
        # unique process identity before declaring the process group gone.
        confirmed = anchor_code is not None and not group_members(identity['pgid'])
        os_code = raw_code if raw_code is None or raw_code >= 0 else 128 - raw_code
        business_code = state.get('application_exit_code')
        expected_signal = stop_started is not None and os_code in (130, 143) and business_code == 0
        successful = (os_code == 0 or expected_signal) and business_code in (None, 0) and not forced and not role_exit.get('descendants_remaining')
        if descriptor['role'] in ('produce', 'consume', 'topic') and business_code is None:
            successful = False
        if (state.get('last_frame') or {}).get('state') == 'failed':
            successful = False
        with lock(directory):
            state.update(state='stopped' if successful and confirmed else 'failed', stop_confirmed=confirmed,
                         os_returncode=raw_code, exit_code=os_code, application_exit_code=business_code,
                         anchor_returncode=anchor_code, role_os_returncode=role_exit.get('os_returncode'),
                         stop_reason=state.get('stop_reason', 'completed' if successful else 'process_failed'), forced=forced)
            atomic(directory / 'state.json', state)
    except Exception:
        confirmed = process is None
        if process is not None:
            identity = state.get('anchor') if state else None
            signal_owned(identity, signal.SIGKILL)
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            confirmed = process.poll() is not None and not group_members(identity['pgid']) if identity and identity.get('pgid') else process.poll() is not None
        if state is not None:
            with lock(directory):
                state.update(state='failed', stop_confirmed=confirmed, stop_reason='supervisor_failure')
                atomic(directory / 'state.json', state)
    finally:
        selector.close()
        if process:
            for stream in (process.stdout, process.stderr):
                if stream:
                    stream.close()
