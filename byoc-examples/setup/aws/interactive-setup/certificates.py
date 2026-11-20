"""Local PEM validation and user-run certificate preparation."""
import re
import shlex
import subprocess
import ssl
import time
import tempfile
from pathlib import Path
from core import SetupError, write_private


def openssl(args, content):
    result = subprocess.run(['openssl', *args], input=content, text=True, capture_output=True, timeout=20)
    if result.returncode: raise SetupError('Certificate/key validation failed. Check PEM format, expiry, key encryption and matching materials.')
    return result.stdout


def certificate_info(pem, domain=None, ca=False):
    openssl(['x509','-noout','-checkend','0'], pem)
    start = openssl(['x509','-noout','-startdate'], pem).strip().split('=',1)[1]
    if ssl.cert_time_to_seconds(start) > time.time(): raise SetupError('Certificate is not valid yet.')
    if domain:
        names = openssl(['x509','-noout','-ext','subjectAltName'], pem)
        domain = domain.rstrip('.').lower()
        if '*.' + domain not in re.findall(r'dns:([^,\s]+)', names.lower()):
            raise SetupError(f'Certificate SAN must include *.{domain} for generated broker hostnames.')
    if ca:
        info = openssl(['x509','-noout','-ext','basicConstraints'], pem)
        if 'CA:TRUE' not in info: raise SetupError('Client CA must have basicConstraints CA:TRUE.')


def validate_key(cert, key):
    public = openssl(['x509','-pubkey','-noout'], cert)
    key_public = openssl(['pkey','-pubout','-passin','pass:'], key)
    if public.strip() != key_public.strip(): raise SetupError('Certificate and private key do not match.')


def verify_server_chain(chain, trust, domain):
    """Validate the private-zone certificate as CMP does, 30 days ahead."""
    certificate_info(chain, domain)
    certificate_info(trust, ca=True)
    entries = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', chain, re.S)
    if not entries:
        raise SetupError('Enter a PEM server certificate chain.')
    with tempfile.TemporaryDirectory() as temp:
        directory = Path(temp)
        leaf, intermediates, authorities = (directory / name for name in ('server.pem', 'intermediate.pem', 'ca.pem'))
        leaf.write_text(entries[0] + '\n')
        authorities.write_text(trust)
        args = ['verify', '-trusted', str(authorities), '-partial_chain', '-purpose', 'sslserver',
                '-verify_hostname', 'broker.' + domain.rstrip('.'), '-attime', str(int(time.time()) + 30 * 86400)]
        if len(entries) > 1:
            intermediates.write_text('\n'.join(entries[1:]) + '\n')
            args += ['-untrusted', str(intermediates)]
        try:
            openssl([*args, str(leaf)], '')
        except SetupError:
            raise SetupError('The CA bundle must verify the server chain for the selected zone 30 days from now. Check the issuers, SAN and certificate expiry.') from None


def preparation(directory, domain):
    domain = domain.rstrip('.')
    if not re.fullmatch(r'[a-zA-Z0-9.-]+', domain): raise SetupError('Invalid certificate domain.')
    # CSR lets the user obtain a chain from their own CA without installing a test CA.
    path = directory / 'prepare-certificate.sh'
    write_private(path, '#!/usr/bin/env bash\nset -euo pipefail\numask 077\n'
        'cd -- "$(dirname -- "$0")"\n[ ! -e server.key ] && [ ! -e server.csr ]\n'
        'openssl req -new -newkey rsa:3072 -nodes -keyout server.key -out server.csr '
        f'-subj {shlex.quote("/CN=*."+domain)} -addext {shlex.quote("subjectAltName=DNS:*."+domain)}\n'
        "printf '%s\\n' 'Submit server.csr to your CA. Return with the issued PEM chain and server.key.'\n")
    return path
