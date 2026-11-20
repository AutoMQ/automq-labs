#!/usr/bin/env python3
"""Emit curl configuration for one CMP create request; never sends requests itself."""
import argparse
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


CREATE_PATH = '/api/v1/instances'
CREATE_CURL = ('curl --disable --config request.curl --fail-with-body --silent --show-error '
               '--connect-timeout 10 --max-time 120 --output create-response.json')


def signature(body, access_key, secret_key, now, method="POST", path=CREATE_PATH):
    stamp = now.astimezone(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    day = stamp[:8]
    scope = day + '/private/cmp/cmp_request'
    signed = 'x-automq-date'
    canonical = '\n'.join([method, path, '', signed + ':' + stamp + '\n', signed, hashlib.sha256(body).hexdigest()])
    to_sign = '\n'.join(['AUTOMQ-HMAC-SHA256', stamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
    key = ('AUTOMQ' + secret_key).encode()
    for part in [day, 'private', 'cmp', 'cmp_request']:
        key = hmac.new(key, part.encode(), hashlib.sha256).digest()
    digest = hmac.new(key, to_sign.encode(), hashlib.sha256).hexdigest()
    auth = f'AUTOMQ-HMAC-SHA256 Credential={access_key}/{scope}, SignedHeaders={signed}, Signature={digest}'
    return stamp, auth


def console_origin(url):
    parsed = urlsplit(url)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or parsed.path not in ('', '/') or parsed.query or parsed.fragment
            or any(c.isspace() or ord(c) < 32 for c in url)):
        raise ValueError('Use the Console origin, such as http://127.0.0.1:8080, without a path or credentials.')
    return url.rstrip('/')


def service_credentials(credential_file):
    credentials = json.loads(Path(credential_file).read_text())
    ak, sk = credentials['accessKey'], credentials['secretKey']
    if any(isinstance(v, str) and v.startswith('REPLACE_') for v in [ak, sk]):
        raise ValueError('Replace accessKey and secretKey in cmp-credentials.json with your existing CMP service-account credentials.')
    if not all(isinstance(v, str) and re.fullmatch(r'[A-Za-z0-9]+', v) for v in [ak, sk]):
        raise ValueError('This command supports CMP alphanumeric access keys and secret keys.')
    return ak, sk


def curl_config(url, request_file, credential_file, now=None, request_reference=None):
    origin = console_origin(url)
    ak, sk = service_credentials(credential_file)
    request = Path(request_file).resolve()
    body = request.read_bytes()
    json.loads(body)
    stamp, auth = signature(body, ak, sk, now or datetime.now(timezone.utc))
    def quoted(v):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'
    return '\n'.join([
        'url = ' + quoted(origin + CREATE_PATH), 'request = "POST"',
        'header = "Content-Type: application/json"', 'header = ' + quoted('X-automq-date: ' + stamp),
        'header = ' + quoted('Authorization: ' + auth), 'data-binary = ' + quoted('@' + (request_reference or str(request))),
    ]) + '\n'


def generate_bundle(url, request_file, credential_file, output):
    # Read and sign an immutable snapshot. No network calls or command execution.
    body = Path(request_file).read_bytes()
    output = Path(output).resolve()
    output.mkdir(mode=0o700, parents=True, exist_ok=False)
    def save(name, content):
        with os.fdopen(os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as stream:
            stream.write(content if isinstance(content, bytes) else content.encode())
    try:
        save('request.json', body)
        config = curl_config(url, output / 'request.json', credential_file, request_reference='request.json')
        save('request.curl', config)
        save('create-target.json', json.dumps({'consoleUrl': console_origin(url)}) + '\n')
        save('create-cluster.sh', '''#!/usr/bin/env bash
set -euo pipefail
umask 077
cd -- "$(dirname -- "$0")"
# Read BEFORE-CREATE.md. Run after Home is ACTIVE and a UsageBased subscription or trial is available.
SETUP_CURL_STATUS=0
''' + CREATE_CURL + r''' || SETUP_CURL_STATUS=$?
if [ "$SETUP_CURL_STATUS" -ne 0 ]; then
  if [ -f create-response.json ] && grep -Eq '"code"[[:space:]]*:[[:space:]]*"Instance.NoAvailableSubscription"' create-response.json; then
    printf '%s\n' 'CMP rejected creation because the environment has no available UsageBased subscription. Home ACTIVE does not prove subscription availability. Check the subscription or trial and allow CMP to refresh its state.' >&2
  else
    printf '%s\n' 'Request failed or its outcome is unknown. Inspect create-response.json and Console tasks before retrying.' >&2
  fi
  exit "$SETUP_CURL_STATUS"
fi
printf '%s\n' 'Response saved to create-response.json. Check Console for task status.'
''')
        save('BEFORE-CREATE.md', '''# Before creating the cluster

1. Complete Console installation, initialization and IAM authorization.
2. Wait for Home to show ACTIVE. CMP uploads environment metadata to the Ops Bucket and Home refreshes it asynchronously (about 60 seconds per job in the reviewed code).
3. Verify that this environment has an available UsageBased subscription or trial.
4. Run create-cluster.sh on a machine that can reach the selected Console URL.

If Home remains INSTALLED, check Console initialization, the Ops Bucket policy, environment metadata and Home synchronization. If CMP returns Instance.NoAvailableSubscription, check billing availability before signing and submitting again.
''')
    except Exception:
        for name in ['request.json', 'request.curl', 'create-target.json', 'create-cluster.sh', 'BEFORE-CREATE.md']:
            (output / name).unlink(missing_ok=True)
        output.rmdir()
        raise
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('console_url')
    parser.add_argument('--request', default='cluster-request.json')
    parser.add_argument('--credentials', default='cmp-credentials.json')
    parser.add_argument('--output', required=True, help='New directory for the signed curl bundle')
    args = parser.parse_args()
    try:
        output = generate_bundle(args.console_url, args.request, args.credentials, args.output)
        print(f'Generated signed curl bundle in {output}.')
        print('From that directory on a machine that can reach Console, run:')
        print(f'umask 077 && {CREATE_CURL}')
        print('See BEFORE-CREATE.md for prerequisites or run bash create-cluster.sh for error handling.')
    except (ValueError, KeyError, OSError):
        print('Cannot sign request. Check Console URL, request JSON and CMP credentials; replace credential placeholders before execution.', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
