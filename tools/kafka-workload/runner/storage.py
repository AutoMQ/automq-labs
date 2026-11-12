"""Private atomic state and Linux process identities; no PID-only signalling."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import stat
import tempfile
import time

from .schema import ValidationError, absolute_path, identifier


def private_dir(path):
    path = Path(path)
    # Refuse even intermediate symlinks; the installation root is explicit.
    if path.resolve() != path:
        raise ValidationError('state directories must not traverse symlinks')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise ValidationError('directory ownership mismatch')
    path.chmod(0o700)
    return path


def root_path(value):
    return private_dir(Path(absolute_path(value, 'remote_root')))


def atomic(path, value):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            os.fchmod(stream.fileno(), 0o600)
            json.dump(value, stream, separators=(',', ':'), allow_nan=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def read_json(path):
    path = Path(path)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise ValidationError('state file ownership or permissions mismatch')
    if info.st_size > 1024 * 1024:
        raise ValidationError('state file too large')
    with path.open(encoding='utf-8') as stream:
        return json.load(stream)


@contextlib.contextmanager
def lock(directory, name='.lock'):
    directory = private_dir(Path(directory))
    fd = os.open(str(directory / name), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if info.st_uid != os.geteuid() or not stat.S_ISREG(info.st_mode):
            raise ValidationError('lock ownership mismatch')
        os.fchmod(fd, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def task_dir(root, task_id):
    identifier(task_id, 'task_id')
    return private_dir(private_dir(Path(root) / 'state') / task_id)


def boot_id():
    return Path('/proc/sys/kernel/random/boot_id').read_text().strip()


def process_identity(pid):
    if type(pid) is not int or pid <= 0:
        return None
    try:
        data = Path('/proc/%d/stat' % pid).read_text()
        fields = data[data.rfind(')') + 2:].split()
        if fields[0] == 'Z':
            return None
        return {'pid': int(pid), 'pgid': int(fields[2]), 'pid_start_ticks': int(fields[19])}
    except (OSError, ValueError, IndexError):
        return None


def same_process(expected):
    current = process_identity(expected.get('pid', -1))
    return bool(current and all(current[k] == expected.get(k) for k in ('pid', 'pgid', 'pid_start_ticks')))


def utc_now():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def group_members(pgid):
    members = []
    for path in Path('/proc').glob('[0-9]*'):
        identity = process_identity(int(path.name))
        if identity and identity['pgid'] == pgid:
            members.append(identity)
    return members
