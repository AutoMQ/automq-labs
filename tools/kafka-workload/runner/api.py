"""Public Python API used by the standalone launcher and case package."""
import base64
import json
from pathlib import Path

from .schema import check_requirements, load_runner
from .transport import AwsSsmTransport, TransportError


def check(runner, requirements=None, *, transport=None, deadline=None):
    """Check an existing target; never install, upload credentials or change IAM.

    requirements: remote_connection_file (absolute remote path), endpoints
    [{host, port}], expected_zone_id, tools, capture=False and java=True.
    AZ/capture become blocking only when explicitly requested. TCP connect
    probes send no Kafka application data and do not establish source proof.
    """
    config = load_runner(runner)
    requirements = check_requirements(requirements)
    transport = transport or (AwsSsmTransport(config) if deadline is None else AwsSsmTransport(config, deadline=deadline))
    caller = transport.caller_identity()
    source = Path(__file__).with_name("preflight.py").read_text(encoding="utf-8")
    payload = base64.b64encode(json.dumps([requirements, config.instance_id]).encode()).decode("ascii")
    source += "\nimport base64\n_r, _i = json.loads(base64.b64decode('%s'))\nprint(json.dumps(run_check(_r, _i), separators=(',', ':')))\n" % payload
    encoded = base64.b64encode(source.encode()).decode("ascii")
    command = "python3 -c \"import base64; exec(compile(base64.b64decode('%s'), '<runner-check>', 'exec'))\"" % encoded
    result = transport.run(command, timeout_seconds=60)
    if (result.get("schema_version") != 1 or not isinstance(result.get("ok"), bool) or
            not isinstance(result.get("identity"), dict) or not isinstance(result.get("issues"), list)):
        raise TransportError("remote check returned an invalid envelope")
    if result["identity"].get("instance_id") != config.instance_id:
        result["ok"] = False
        result["issues"].append({"code": "target_identity_mismatch", "blocking": True,
                                 "remediation": "Correct the runner instance target before starting remote work."})
    result["management_identity"] = caller
    result["target"] = {"instance_id": config.instance_id, "region": config.region,
                        "remote_root": config.remote_root, "transport": "ssm"}
    return result


def _remote(runner, operation, request, transport=None, deadline=None):
    import shlex
    config = load_runner(runner)
    transport = transport or (AwsSsmTransport(config) if deadline is None else AwsSsmTransport(config, deadline=deadline))
    encoded = base64.b64encode(json.dumps(request, separators=(',', ':')).encode()).decode('ascii')
    # All variable shell words are quoted; the request is secret-free base64.
    command = ('cd ' + shlex.quote(config.remote_root + '/current') +
               ' && PYTHONDONTWRITEBYTECODE=1 python3 -m runner.remote_agent ' + operation +
               ' --root ' + shlex.quote(config.remote_root) + ' --request-b64 ' + shlex.quote(encoded))
    result = transport.run(command, timeout_seconds=30)
    if result.get('error'):
        raise TransportError('remote operation refused: ' + result.get('remediation', 'verify installed bundle and task ownership'))
    return result


def install(runner, artifact_s3_uri, sha256, *, transport=None):
    """Explicitly deploy a secret-free, SHA256-pinned private S3 tar bundle."""
    import re
    from .schema import ValidationError
    config = load_runner(runner)
    if not isinstance(sha256, str) or not re.fullmatch('[0-9a-f]{64}', sha256):
        raise ValidationError('artifact SHA256 must be lowercase hexadecimal')
    if not isinstance(artifact_s3_uri, str) or not re.fullmatch(r's3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/[^\s\x00-\x1f]+', artifact_s3_uri):
        raise ValidationError('artifact must be an explicit private S3 object URI')
    # Bootstrap only the installer and its two standard-library-only modules;
    # ordinary execution always uses the installed, manifest-checked release.
    sources = {name: Path(__file__).with_name(name + '.py').read_text() for name in ('schema', 'storage', 'installer')}
    request = base64.b64encode(json.dumps([sources, config.remote_root, artifact_s3_uri, sha256]).encode()).decode('ascii')
    script = """import base64,json,sys,types
sys.dont_write_bytecode=True
sources,root,uri,sha=json.loads(base64.b64decode(REQUEST))
package=types.ModuleType('runner');package.__path__=[];sys.modules['runner']=package
for name in ('schema','storage','installer'):
 module=types.ModuleType('runner.'+name);module.__package__='runner';sys.modules['runner.'+name]=module
 exec(compile(sources[name],'<installer-bootstrap>','exec'),module.__dict__)
try:
 result=sys.modules['runner.installer'].install_s3(root,uri,sha)
except Exception:
 result={'schema_version':1,'error':'installation_failed','remediation':'Verify SHA256, safe manifest, remote AWS CLI and existing private S3 GetObject permission. No IAM is changed.'}
print(json.dumps(result,separators=(',',':')))
""".replace('REQUEST', repr(request))
    encoded = base64.b64encode(script.encode()).decode('ascii')
    command = "python3 -c \"import base64;exec(compile(base64.b64decode('%s'),'<installer-bootstrap>','exec'))\"" % encoded
    result = (transport or AwsSsmTransport(config)).run(command, timeout_seconds=180)
    if result.get('error'):
        raise TransportError('explicit artifact install failed; verify private S3 access, SHA256, safe bundle and remote dependencies')
    return result


def start(runner, descriptor, *, transport=None, deadline=None):
    from .schema import task_descriptor
    config = load_runner(runner)
    descriptor = task_descriptor(descriptor, config)
    return _remote(config, 'start', {'descriptor': descriptor, 'expected_instance_id': config.instance_id}, transport, deadline)


def snapshot(runner, task_id, controller_id=None, renew=False, *, transport=None, deadline=None):
    import time
    from .schema import identifier, ValidationError
    identifier(task_id, 'task_id')
    if type(renew) is not bool:
        raise ValidationError('renew must be boolean')
    if renew:
        identifier(controller_id, 'controller_id')
    started = time.monotonic()
    result = _remote(runner, 'snapshot', {'task_id': task_id, 'controller_id': controller_id, 'renew': renew}, transport, deadline)
    rtt = time.monotonic() - started
    age = result.get('frame_age_ms')
    result['remote_frame_age_ms'] = age
    result['frame_age_ms'] = age + int(rtt * 1000) if isinstance(age, (int, float)) else None
    result['poll_rtt_seconds'] = rtt
    from datetime import datetime, timezone
    result['receipt_time'] = datetime.now(timezone.utc).isoformat()
    result['fresh'] = result.get('state') in ('ready', 'running') and result['frame_age_ms'] is not None and result['frame_age_ms'] <= 15000
    return result


def _unconfirmed(task_id, controller_id, error='transport_unavailable'):
    return {'schema_version': 1, 'task_id': task_id, 'controller_id': controller_id,
            'state': 'disconnected', 'stop_confirmed': False, 'fresh': False,
            'frame_age_ms': None, 'last_frame': None, 'error': error,
            'recovery': {'status': 'run-remote --runner RUNNER.json status --task-id ' + task_id,
                         'stop': 'run-remote --runner RUNNER.json stop --task-id ' + task_id},
            'message': 'Stop unconfirmed; retain the controller state and retry status/stop. The remote lease and maximum runtime remain bounded.'}


def stop(runner, task_id, controller_id, *, transport=None, deadline=None):
    import time
    from .schema import identifier
    identifier(task_id, 'task_id')
    identifier(controller_id, 'controller_id')
    stop_deadline = time.monotonic() + 20
    if deadline is not None:
        stop_deadline = min(stop_deadline, deadline)
    try:
        result = _remote(runner, 'stop', {'task_id': task_id, 'controller_id': controller_id}, transport, deadline)
        while not result.get('stop_confirmed') and time.monotonic() < stop_deadline:
            time.sleep(0.5)
            result = snapshot(runner, task_id, transport=transport, deadline=deadline)
        if not result.get('stop_confirmed'):
            result.update(_unconfirmed(task_id, controller_id, 'remote_stop_unconfirmed'))
        return result
    except TransportError:
        return _unconfirmed(task_id, controller_id)


def attach(runner, task_id, controller_id):
    """Yield fresh short snapshots, renewing only this role's own lease.

    KeyboardInterrupt propagates to the caller, which must call stop and retain
    the returned unconfirmed recovery identity if the management link is down.
    """
    import time
    config = load_runner(runner)
    previous = None
    while True:
        try:
            result = snapshot(config, task_id, controller_id, renew=True)
        except TransportError:
            yield _unconfirmed(task_id, controller_id)
            return
        now = time.monotonic()
        key = (result.get('frame_seq'), result.get('release'))
        age = result.get('frame_age_ms')
        if previous and key == previous[0] and age is not None:
            # A repeated frame cannot become younger even if a remote agent
            # incorrectly reports a smaller age on its next snapshot.
            age = max(age, previous[2] + int((now - previous[1]) * 1000))
            result['frame_age_ms'] = age
        if age is not None:
            previous = (key, now, age)
        result['fresh'] = result.get('state') in ('ready', 'running') and age is not None and age <= 15000
        result['stream_state'] = 'current' if result['fresh'] else 'stale'
        yield result
        if result.get('state') in ('stopped', 'failed'):
            return
        if result.get('state') == 'unknown':
            return
        time.sleep(config.poll_seconds)
