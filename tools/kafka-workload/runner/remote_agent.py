"""Short control operations for detached, independently leased remote roles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time

from .installer import current_release, validate_release
from .schema import ValidationError, identifier, task_descriptor
from .storage import atomic, boot_id, group_members, lock, private_dir, process_identity, read_json, root_path, same_process, task_dir, utc_now

TERMINAL = {'stopped', 'failed'}


def trusted_argv(root, release, descriptor):
    role, argv = descriptor['role'], list(descriptor['argv'])
    manifest = validate_release(release)
    scope_id = descriptor.get('scope_id')
    ledger = None
    if scope_id:
        scopes = Path(root) / 'state' / 'scopes'
        info = scopes.lstat()
        if scopes.is_symlink() or info.st_uid != 0 or stat.S_IMODE(info.st_mode) & 0o077:
            raise ValidationError('scope ledger directory must be root-owned mode 0700')
        ledger_path = scopes / (scope_id + '.json')
        info = ledger_path.lstat()
        if info.st_uid != 0:
            raise ValidationError('scope ledger must be root-owned')
        ledger = read_json(ledger_path)
        expected = 'az-' + hashlib.sha256(scope_id.encode()).hexdigest()[:10]
        if ledger.get('owner') != scope_id or ledger.get('namespace') != expected or ledger.get('state') != 'prepared':
            raise ValidationError('scope namespace ownership/state mismatch')
    if role in ('watch', 'scope-prepare', 'scope-cleanup'):
        if 'watch' not in manifest['features']:
            raise ValidationError('installed bundle lacks watch feature; explicitly install a case bundle')
        prefix = ['python3', '-m', 'cross_az.collector'] if role == 'watch' else ['python3', '-m', 'cross_az.scope', role.split('-')[1]]
        if argv[:len(prefix)] != prefix or argv[len(prefix):len(prefix)+1] != ['--spec-json'] or len(argv) != len(prefix) + 2:
            raise ValidationError('untrusted case entry argv')
        try:
            spec = json.loads(argv[-1])
        except ValueError:
            raise ValidationError('invalid case spec JSON') from None
        if (not isinstance(spec, dict) or spec.get('remote_root') != str(root) or
                spec.get('run_id') != descriptor['run_id'] or spec.get('phase') != descriptor['phase']):
            raise ValidationError('case spec ownership mismatch')
        identifier(spec.get('scope_id'), 'scope_id')
        if role == 'watch' and spec['scope_id'] != scope_id:
            raise ValidationError('watch must reference its prepared scope')
        return [sys.executable] + argv[1:]  # collector stays in host namespace
    if scope_id:
        if role not in ('produce', 'consume') or argv[:4] != ['ip', 'netns', 'exec', ledger['namespace']]:
            raise ValidationError('scoped workload must use its ledger namespace')
        prefix, argv = argv[:4], argv[4:]
    else:
        prefix = []
    if not argv or argv[0] not in ('./workload', 'workload', str(release / 'workload')):
        raise ValidationError('workload must use the installed release entry')
    if len(argv) < 2 or argv[1] != role:
        raise ValidationError('workload role differs from descriptor')
    first = 2
    allowed = {'--config', '--topic'}
    if role == 'topic':
        if len(argv) < 3 or argv[2] not in ('create', 'describe'):
            raise ValidationError('only explicit topic create/describe are supported')
        first = 3
        if argv[2] == 'create':
            allowed.add('--partitions')
    else:
        allowed |= {'--run-id', '--duration-seconds', '--max-messages', '--max-errors'}
        allowed |= {'--group', '--start-position'} if role == 'consume' else {'--rate-mibps', '--record-bytes', '--compression', '--partition-mode'}
    options = {}
    if (len(argv) - first) % 2:
        raise ValidationError('workload options require values')
    for i in range(first, len(argv), 2):
        if argv[i] not in allowed or argv[i] in options:
            raise ValidationError('unsupported or duplicate workload option; credentials are file-only')
        options[argv[i]] = argv[i+1]
    from .schema import absolute_path
    config = Path(absolute_path(options.get('--config'), '--config'))
    info = config.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) & 0o077 or not os.access(config, os.R_OK):
        raise ValidationError('Kafka config must be a readable restricted regular remote file')
    return prefix + [str(release / 'workload')] + argv[1:]


def _state(directory):
    return read_json(Path(directory) / 'state.json')


def start_task(root, descriptor, expected_instance_id=None):
    root = root_path(root)
    descriptor = task_descriptor(descriptor)
    directory = task_dir(root, descriptor['task_id'])
    with lock(directory):
        if (directory / 'descriptor.json').exists():
            if read_json(directory / 'descriptor.json') != descriptor:
                raise ValidationError('Conflict: task ID already belongs to another descriptor/controller')
            return snapshot_task(str(root), descriptor['task_id'], _locked=True)
        release = current_release(root)
        argv = trusted_argv(root, release, descriptor)
        identity = None
        if expected_instance_id:
            from .preflight import run_check
            preflight = run_check({'java': False}, expected_instance_id)
            identity = preflight['identity']
            if not identity.get('identity_verified'):
                raise ValidationError('actual remote instance identity mismatch')
        atomic(directory / 'descriptor.json', descriptor)
        now = time.monotonic()
        state = {'schema_version': 1, 'task_id': descriptor['task_id'], 'controller_id': descriptor['controller_id'],
                 'role': descriptor['role'], 'run_id': descriptor['run_id'], 'phase': descriptor['phase'],
                 'state': 'starting', 'release': str(release), 'argv': argv, 'boot_id': boot_id(),
                 'started_mono': now, 'frame_seq': 0, 'last_frame': None, 'ready_frame': None,
                 'frame_mono': None, 'stop_confirmed': False, 'exit_code': None, 'os_returncode': None,
                 'application_exit_code': None, 'stderr_tail': [], 'identity': identity}
        atomic(directory / 'state.json', state)
        atomic(directory / 'lease.json', {'controller_id': descriptor['controller_id'], 'deadline': now + descriptor['lease_seconds']})
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', PYTHONPATH=str(release))
        try:
            process = subprocess.Popen([sys.executable, '-m', 'runner.remote_agent', '_supervise', '--root', str(root), '--task-id', descriptor['task_id']],
                                       cwd=str(release), env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL, close_fds=True, start_new_session=True)
            state['supervisor'] = process_identity(process.pid)
            atomic(directory / 'state.json', state)
        except OSError:
            state.update(state='failed', stop_confirmed=True, stop_reason='supervisor_start_failed', exit_code=2)
            atomic(directory / 'state.json', state)
            raise ValidationError('detached supervisor could not start') from None
    # Return immediately; snapshot is a separate short operation, not final output.
    return snapshot_task(str(root), descriptor['task_id'])


def snapshot_task(root, task_id, controller_id=None, renew=False, _locked=False):
    root = root_path(root)
    directory = task_dir(root, task_id)
    if not _locked:
        with lock(directory):
            return snapshot_task(str(root), task_id, controller_id, renew, _locked=True)
    descriptor = read_json(directory / 'descriptor.json')
    state = _state(directory)
    now = time.monotonic()
    same_boot = state.get('boot_id') == boot_id()
    if renew:
        if controller_id != descriptor['controller_id']:
            raise ValidationError('controller ownership mismatch; lease not renewed')
        if state['state'] not in TERMINAL and same_boot:
            atomic(directory / 'lease.json', {'controller_id': controller_id, 'deadline': now + descriptor['lease_seconds']})
    lease = read_json(directory / 'lease.json')
    if state['state'] not in TERMINAL:
        supervisor = state.get('supervisor')
        if not same_boot or not supervisor or not same_process(supervisor):
            # Never claim a child stopped solely because its supervisor vanished.
            state = dict(state, state='unknown', stop_confirmed=False, stop_reason='supervisor_unavailable')
    state = dict(state)
    state.pop('argv', None)
    frame_mono = state.pop('frame_mono', None)
    state['remote_time'] = utc_now()
    state['frame_age_ms'] = max(0, int((now - frame_mono) * 1000)) if frame_mono is not None and same_boot else None
    state['lease_remaining_seconds'] = max(0, lease['deadline'] - now) if same_boot else 0
    state['fresh'] = state['state'] in ('ready', 'running') and state['frame_age_ms'] is not None and state['frame_age_ms'] <= 15000
    return state


def request_stop(root, task_id, controller_id):
    directory = task_dir(root_path(root), task_id)
    with lock(directory):
        descriptor = read_json(directory / 'descriptor.json')
        if controller_id != descriptor['controller_id']:
            raise ValidationError('controller ownership mismatch; task not stopped')
        state = _state(directory)
        if state['state'] in TERMINAL and state.get('stop_confirmed'):
            return snapshot_task(root, task_id, _locked=True)
        atomic(directory / 'stop.json', {'controller_id': controller_id, 'requested_mono': time.monotonic()})
        if state.get('boot_id') != boot_id():
            state.update(state='failed', stop_confirmed=True, stop_reason='host_rebooted', exit_code=None)
            atomic(directory / 'state.json', state)
        elif not state.get('supervisor') or not same_process(state['supervisor']):
            # Recover an orphan using the saved unique child identity, never
            # an arbitrary PID. Keep unknown application/OS exit results visible.
            from .supervisor import signal_owned
            anchor = state.get('anchor') or state
            members = group_members(anchor['pgid']) if anchor.get('pgid') else []
            known = members if same_process(anchor) else []
            signal_owned(anchor, signal.SIGTERM, known)
            deadline = time.monotonic() + 10
            while known and any(same_process(m) for m in known) and time.monotonic() < deadline:
                time.sleep(0.1)
            if known and any(same_process(m) for m in known):
                signal_owned(anchor, signal.SIGKILL, known)
                deadline = time.monotonic() + 2
                while any(same_process(m) for m in known) and time.monotonic() < deadline:
                    time.sleep(0.1)
            confirmed = not group_members(anchor['pgid']) if anchor.get('pgid') else False
            state.update(state='failed', stop_confirmed=confirmed, stop_reason='supervisor_lost_recovery', exit_code=None)
            atomic(directory / 'state.json', state)
    return snapshot_task(root, task_id)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('operation', choices=('start', 'snapshot', 'stop', '_supervise', '_role'))
    parser.add_argument('--root', required=True)
    parser.add_argument('--task-id')
    parser.add_argument('--request-b64')
    args = parser.parse_args(argv)
    try:
        if args.operation == '_role':
            from .supervisor import role_anchor
            return role_anchor(args.root, args.task_id)
        if args.operation == '_supervise':
            from .supervisor import supervise
            supervise(args.root, args.task_id)
            return 0
        import base64
        request = json.loads(base64.b64decode(args.request_b64)) if args.request_b64 else {}
        if args.operation == 'start':
            value = start_task(args.root, request['descriptor'], request.get('expected_instance_id'))
        elif args.operation == 'snapshot':
            value = snapshot_task(args.root, request['task_id'], request.get('controller_id'), request.get('renew', False))
        else:
            value = request_stop(args.root, request['task_id'], request['controller_id'])
        print(json.dumps(value, separators=(',', ':'), allow_nan=False))
        return 0
    except (OSError, ValueError, KeyError, ValidationError) as error:
        # Do not expose raw process, path, properties, or JSON parser exceptions.
        print(json.dumps({'schema_version': 1, 'error': 'remote_operation_failed',
                          'remediation': str(error) if isinstance(error, ValidationError) else 'Verify installed bundle, task/controller ownership, permissions and remote arguments.'}))
        return 0  # complete error envelope remains readable by the transport


if __name__ == '__main__':
    sys.exit(main())
