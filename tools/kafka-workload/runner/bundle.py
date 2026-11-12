"""Build a secret-free runtime tarball; never upload it or include config files."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile

from .schema import ValidationError


def build_bundle(output, workload_dir=None, case_dir=None):
    root = Path(workload_dir) if workload_dir else Path(__file__).resolve().parents[1]
    entries = {'workload': root / 'workload', 'workload.jar': root / 'target' / 'workload.jar'}
    for path in sorted((root / 'runner').glob('*.py')):
        entries['runner/' + path.name] = path
    features = ['workload']
    if case_dir:
        package = Path(case_dir)
        if package.name != 'cross_az':
            package /= 'cross_az'
        if not all((package / name).is_file() for name in ('__init__.py', 'scope.py', 'collector.py')):
            raise ValidationError('case_dir must contain the cross_az package entry points')
        for path in sorted(package.glob('*.py')):
            entries['cross_az/' + path.name] = path
        features.append('watch')
    for path in entries.values():
        if path.is_symlink() or not path.is_file():
            raise ValidationError('build requires the launcher, fat target/workload.jar and regular Python module files')
    content = {name: path.read_bytes() for name, path in entries.items()}
    manifest = {'schema_version': 1, 'features': features,
                'files': {name: hashlib.sha256(data).hexdigest() for name, data in content.items()}}
    content['manifest.json'] = json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Uncompressed deterministic tar avoids gzip timestamp variation and allows
    # callers to compare bundle SHA256 for an identical source/JAR checkout.
    with output.open('wb') as stream:
        output.chmod(0o600)
        with tarfile.open(fileobj=stream, mode='w', format=tarfile.USTAR_FORMAT) as archive:
            for name, data in sorted(content.items()):
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), 0o700 if name == 'workload' else 0o600, 0
                info.uid = info.gid = 0
                info.uname = info.gname = ''
                archive.addfile(info, io.BytesIO(data))
    sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
    return {'schema_version': 1, 'artifact': str(output), 'sha256': sha256, 'manifest': manifest}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, help='local runtime .tar output (no upload)')
    parser.add_argument('--case-dir', help='optional local case directory containing cross_az/')
    args = parser.parse_args(argv)
    try:
        result = build_bundle(args.out, case_dir=args.case_dir)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, ValidationError):
        parser.exit(2, 'bundle: build the fat workload JAR and verify module paths; no artifact was uploaded.\n')


if __name__ == '__main__':
    raise SystemExit(main())
