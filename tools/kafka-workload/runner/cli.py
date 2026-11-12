"""Local control with durable role/controller identities and recovery commands."""
import argparse
import json
from pathlib import Path
import sys
import uuid

from . import api
from .schema import RunnerError, ValidationError, identifier, load_runner
from .storage import atomic, lock, private_dir, read_json


def render(result, as_json):
    if as_json or result.get('manifest'):
        print(json.dumps(result, sort_keys=True), flush=True)
    elif 'dependencies' in result:
        print('Local controller -> SSM %s | Remote host %s | Actual AZ %s | Check %s' % (
            result['target']['instance_id'], result['identity'].get('hostname'), result['identity'].get('zone_id') or 'unverified', 'ready' if result['ok'] else 'not ready'))
        for issue in result['issues']:
            print('%s: %s' % (issue['code'], issue['remediation']))
    else:
        print('Task %s | role %s | state %s | frame %s | age %s ms | fresh %s' % (
            result.get('task_id'), result.get('role'), result.get('state'), result.get('frame_seq'), result.get('frame_age_ms'), result.get('fresh', False)), flush=True)
        identity = result.get('identity') or {}
        print('  Remote host=%s actual_AZ=%s source_frame_time=%s' % (identity.get('hostname', 'unverified'), identity.get('zone_id', 'unverified'), (result.get('last_frame') or {}).get('sample_time')), flush=True)
        frame = result.get('last_frame') or {}
        if frame:
            print('  messages=%s payload_bytes=%s errors=%s OS_exit=%s application_exit=%s' % (
                frame.get('messages'), frame.get('payload_bytes'), frame.get('errors'), result.get('exit_code'), result.get('application_exit_code')), flush=True)
        if result.get('message'):
            print(result['message'], flush=True)


def recovery(args):
    import shlex
    prefix = 'run-remote --runner %s --state-dir %s ' % (shlex.quote(args.runner), shlex.quote(args.state_dir))
    print('Stop unconfirmed. Retain task/controller state.\n' + prefix + 'status --task-id ' + args.task_id + '\n' + prefix + 'stop --task-id ' + args.task_id, file=sys.stderr)


def main(argv=None):
    parser = argparse.ArgumentParser(description='Control an existing remote Linux client over AWS SSM')
    parser.add_argument('--runner', required=True, help='local runner JSON file')
    parser.add_argument('--state-dir', default='.runner-state', help='local private controller state directory')
    commands = parser.add_subparsers(dest='operation', required=True)
    command = commands.add_parser('check', help='read-only identity/dependency checks')
    command.add_argument('--config', dest='remote_connection_file', help='absolute REMOTE Kafka properties path')
    command.add_argument('--requirements', help='local check requirements JSON file')
    command.add_argument('--json', action='store_true')
    command = commands.add_parser('install', help='explicit private S3 artifact deployment')
    command.add_argument('--artifact-s3', required=True)
    command.add_argument('--sha256', required=True)
    command.add_argument('--json', action='store_true')
    command = commands.add_parser('start', help='start one role; attach unless --detach is explicit')
    command.add_argument('--task-id', required=True)
    command.add_argument('--role', required=True, choices=('topic', 'produce', 'consume'))
    command.add_argument('--run-id', required=True)
    command.add_argument('--phase', default='manual')
    command.add_argument('--detach', action='store_true')
    command.add_argument('--json', action='store_true')
    command.add_argument('arguments', nargs=argparse.REMAINDER)
    for name in ('status', 'attach', 'stop'):
        command = commands.add_parser(name)
        command.add_argument('--task-id', required=True)
        command.add_argument('--controller-id', help='owner ID; otherwise use saved private state')
        command.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    try:
        config = load_runner(args.runner)
        if args.operation == 'check':
            requirements = json.loads(Path(args.requirements).read_text()) if args.requirements else {}
            if args.remote_connection_file:
                if not isinstance(requirements, dict):
                    raise ValidationError('requirements must be an object')
                requirements['remote_connection_file'] = args.remote_connection_file
            result = api.check(config, requirements)
            render(result, args.json)
            return 0 if result['ok'] else 2
        if args.operation == 'install':
            print('Explicit install: download the specified S3 bundle, verify SHA256, write a private immutable release and atomically update current; no Kafka properties upload.', file=sys.stderr)
            render(api.install(config, args.artifact_s3, args.sha256), True)
            return 0
        identifier(args.task_id, 'task_id')
        state_dir = private_dir(Path(args.state_dir).resolve())
        path = state_dir / (args.task_id + '.json')
        saved = read_json(path) if path.exists() else None
        target = {k: config.as_dict()[k] for k in ('region', 'instance_id', 'remote_root', 'profile')}
        if saved and saved.get('target') != target:
            raise ValidationError('saved task belongs to a different runner target')
        if args.operation == 'start':
            with lock(state_dir, '.' + args.task_id + '.lock'):
                saved = read_json(path) if path.exists() else None
                arguments = args.arguments[1:] if args.arguments[:1] == ['--'] else args.arguments
                if arguments[:1] != [args.role]:
                    arguments = [args.role] + arguments
                descriptor = {'schema_version': 1, 'task_id': args.task_id, 'controller_id': saved['controller_id'] if saved else uuid.uuid4().hex,
                              'role': args.role, 'run_id': args.run_id, 'phase': args.phase, 'argv': ['./workload'] + arguments}
                if saved and saved.get('descriptor') != descriptor:
                    raise ValidationError('Conflict: saved task descriptor differs; choose a new task ID')
                saved = {'schema_version': 1, 'task_id': args.task_id, 'controller_id': descriptor['controller_id'], 'descriptor': descriptor, 'target': target}
                atomic(path, saved)  # persist before submission, including a lost start acknowledgement
            result = api.start(config, descriptor)
            saved['last_snapshot'] = result
            atomic(path, saved)
            render(result, args.json)
            if args.detach:
                print('Detached role: lease expires without attach renewal; retain --state-dir for status/stop.', file=sys.stderr)
                return 2 if result.get('state') == 'failed' else 0
        elif args.operation == 'status':
            render(api.snapshot(config, args.task_id), args.json)
            return 0
        controller = saved['controller_id'] if saved else getattr(args, 'controller_id', None)
        if not controller:
            raise ValidationError('controller identity required; use original --state-dir or --controller-id')
        if args.operation == 'stop':
            result = api.stop(config, args.task_id, controller)
            render(result, args.json)
            if not result.get('stop_confirmed'):
                recovery(args)
                return 3
            return 0
        try:
            for result in api.attach(config, args.task_id, controller):
                if saved:
                    saved['last_snapshot'] = result
                    atomic(path, saved)
                render(result, args.json)
                if result.get('state') in ('disconnected', 'unknown'):
                    recovery(args)
                    return 3
            if not result.get('stop_confirmed'):
                recovery(args)
                return 3
            return 0 if result.get('state') == 'stopped' else 2
        except KeyboardInterrupt:
            result = api.stop(config, args.task_id, controller)
            if saved:
                saved['last_snapshot'] = result
                atomic(path, saved)
            render(result, args.json)
            if not result.get('stop_confirmed'):
                recovery(args)
                return 3
            return 0 if result.get('state') == 'stopped' else 2
    except KeyboardInterrupt:
        if args.operation in ('start', 'attach') and locals().get('saved'):
            try:
                result = api.stop(config, args.task_id, saved['controller_id'])
                saved['last_snapshot'] = result
                atomic(path, saved)
                render(result, args.json)
                if result.get('stop_confirmed'):
                    return 0 if result.get('state') == 'stopped' else 2
            except KeyboardInterrupt:
                pass
            recovery(args)
            return 3
        if getattr(args, 'task_id', None):
            recovery(args)
        return 130
    except (RunnerError, OSError, ValueError) as error:
        print('runner: ' + (str(error) if isinstance(error, RunnerError) else 'local state/config unavailable; retain task identity and retry status/stop'), file=sys.stderr)
        if getattr(args, 'task_id', None):
            recovery(args)
        return 2


if __name__ == '__main__':
    sys.exit(main())
