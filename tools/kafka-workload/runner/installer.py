"""Explicit S3 artifact installation with bounded, link-free tar extraction."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
import tempfile

from .schema import ValidationError
from .storage import atomic, lock, private_dir, read_json, root_path

MAX_FILE = 128 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
REQUIRED = {'workload', 'workload.jar', 'runner/__init__.py', 'runner/remote_agent.py',
            'runner/storage.py', 'runner/supervisor.py', 'runner/schema.py', 'runner/installer.py',
            'runner/api.py', 'runner/transport.py', 'runner/preflight.py'}


def digest(path):
    result = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def relative(value):
    if not isinstance(value, str) or not value or '\\' in value or any(ord(c) < 32 for c in value):
        raise ValidationError('invalid manifest path')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or str(path) != value or value in ('.', ''):
        raise ValidationError('bundle path escapes or aliases release')
    if value not in ('manifest.json', 'workload', 'workload.jar') and not value.startswith(('runner/', 'cross_az/')):
        raise ValidationError('unexpected bundle path')
    return value


def validate_release(release):
    release = Path(release)
    manifest = read_json(release / 'manifest.json')
    if manifest.get('schema_version') != 1 or not isinstance(manifest.get('features'), list):
        raise ValidationError('invalid bundle manifest')
    files = manifest.get('files')
    if not isinstance(files, dict) or not REQUIRED <= set(files) or 'workload' not in manifest['features']:
        raise ValidationError('bundle lacks required workload/runner entries')
    if set(manifest['features']) - {'workload', 'watch'}:
        raise ValidationError('unsupported bundle features')
    if 'watch' in manifest['features'] and not {'cross_az/__init__.py', 'cross_az/scope.py', 'cross_az/collector.py'} <= set(files):
        raise ValidationError('watch bundle lacks case entry points')
    for name, expected in files.items():
        relative(name)
        if not isinstance(expected, str) or not re.fullmatch('[0-9a-f]{64}', expected):
            raise ValidationError('invalid manifest digest')
        path = release / name
        if path.is_symlink() or path.resolve() != path or not path.is_file() or digest(path) != expected:
            raise ValidationError('installed bundle hash or entry path mismatch')
    return manifest


def extract_bundle(archive, destination):
    destination = private_dir(Path(destination))
    with tarfile.open(archive, 'r:*') as bundle:
        entries, names, total = [], set(), 0
        for entry in bundle:
            if len(entries) >= 200:
                raise ValidationError('too many bundle entries')
            entries.append(entry)
            name = relative(entry.name)
            if name in names or not entry.isfile() or entry.size < 0 or entry.size > MAX_FILE:
                raise ValidationError('bundle has duplicate, linked, special, or oversized entry')
            names.add(name)
            total += entry.size
            if total > MAX_TOTAL:
                raise ValidationError('bundle exceeds total size bound')
        if 'manifest.json' not in names:
            raise ValidationError('bundle size or manifest invalid')
        for entry in entries:
            target = destination / entry.name
            private_dir(target.parent)
            with bundle.extractfile(entry) as source:
                fd = os.open(str(target), os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'wb') as stream:
                    shutil.copyfileobj(source, stream, 1024 * 1024)
            target.chmod(0o700 if entry.name == 'workload' else 0o600)
    manifest = validate_release(destination)
    if names != set(manifest['files']) | {'manifest.json'}:
        raise ValidationError('bundle entries differ from manifest')
    return manifest


def current_release(root):
    root = Path(root)
    current = root / 'current'
    if not current.is_symlink() or current.lstat().st_uid != os.geteuid():
        raise ValidationError('no trusted installed current release; run explicit install')
    release = current.resolve()
    if release.parent != root / 'releases' or not re.fullmatch('[0-9a-f]{64}', release.name):
        raise ValidationError('current points outside immutable releases')
    validate_release(release)
    return release


def install_archive(root, archive, sha256):
    root = root_path(str(root))
    if not re.fullmatch('[0-9a-f]{64}', sha256) or digest(archive) != sha256:
        raise ValidationError('artifact SHA256 mismatch')
    releases = private_dir(root / 'releases')
    with lock(root, '.install.lock'):
        release = releases / sha256
        if release.exists() or release.is_symlink():
            if release.is_symlink() or release.resolve() != release:
                raise ValidationError('unsafe existing release')
            manifest = validate_release(release)
        else:
            staging = Path(tempfile.mkdtemp(prefix='.install-', dir=str(releases)))
            try:
                manifest = extract_bundle(archive, staging)
                os.rename(staging, release)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        current = root / 'current'
        if current.exists() or current.is_symlink():
            current_release(root)  # refuse replacing unrelated user objects
        link = root / ('.current-' + sha256)
        if link.exists() or link.is_symlink():
            raise ValidationError('unexpected installation link')
        try:
            link.symlink_to(release)
            os.replace(link, current)
        finally:
            if link.is_symlink():
                link.unlink()
    return {'schema_version': 1, 'release': str(release), 'sha256': sha256, 'manifest': manifest}


def install_s3(root, artifact_s3_uri, sha256):
    if not isinstance(artifact_s3_uri, str) or not re.fullmatch(r's3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]/[^\s\x00-\x1f]+', artifact_s3_uri):
        raise ValidationError('artifact must be an explicit private S3 object URI')
    if not isinstance(sha256, str) or not re.fullmatch('[0-9a-f]{64}', sha256):
        raise ValidationError('artifact SHA256 must be lowercase hexadecimal')
    root = root_path(root)
    with tempfile.TemporaryDirectory(prefix='.download-', dir=str(root)) as directory:
        archive = Path(directory) / 'bundle.tar.gz'
        try:
            response = subprocess.run(['aws', 's3', 'cp', artifact_s3_uri, str(archive), '--no-progress', '--only-show-errors'],
                                      capture_output=True, timeout=120)
        except (OSError, subprocess.TimeoutExpired):
            raise ValidationError('artifact download unavailable; verify remote AWS CLI and existing S3 GetObject permission') from None
        if response.returncode or not archive.is_file() or archive.stat().st_size > MAX_TOTAL:
            raise ValidationError('artifact download failed or exceeds size bound; no permissions were changed')
        archive.chmod(0o600)
        return install_archive(root, archive, sha256)
