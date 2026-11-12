"""Read-only remote preflight, also usable before a bundle is installed.

This module deliberately has no package imports: the controller sends its source
to the specified SSM target. It never reads Kafka properties contents.
"""
import ipaddress
import json
import os
import platform
import re
import shutil
import socket
import stat
import subprocess
import sys
import time
import urllib.request


_RESOLVE_CODE = """import json, socket, sys
host, port = json.load(sys.stdin)
print(json.dumps(socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)))
"""


def _resolve_addresses(host, port, timeout):
    try:
        ip = ipaddress.ip_address(host)
        family = socket.AF_INET if ip.version == 4 else socket.AF_INET6
        address = (str(ip), port) if ip.version == 4 else (str(ip), port, 0, 0)
        return [(family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", address)]
    except ValueError:
        pass
    # socket timeouts do not bound libc getaddrinfo. Resolve in a short-lived
    # process, killed and waited for by subprocess.run on timeout. A daemon
    # thread would leave unbounded DNS work running after this check returns.
    try:
        response = subprocess.run([sys.executable, "-c", _RESOLVE_CODE],
                                  input=json.dumps([host, port]), capture_output=True,
                                  text=True, timeout=timeout)
        if response.returncode or len(response.stdout) > 65536:
            raise OSError("endpoint resolution failed")
        addresses = json.loads(response.stdout)
        if not isinstance(addresses, list) or not addresses:
            raise ValueError()
        return addresses
    except (OSError, ValueError, subprocess.TimeoutExpired):
        raise OSError("endpoint resolution failed or timed out") from None


def _tcp_probe(host, port, timeout):
    deadline = time.monotonic() + timeout
    addresses = _resolve_addresses(host, port, timeout)
    for family, kind, protocol, _canonical, address in addresses:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            with socket.socket(family, kind, protocol) as connection:
                connection.settimeout(remaining)
                connection.connect(tuple(address))
            return
        except OSError:
            pass
    raise OSError("endpoint connect failed or timed out")


def _metadata():
    # Never send IMDS requests through a user-configured proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = "http://169.254.169.254/latest/"
    try:
        req = urllib.request.Request(base + "api/token", method="PUT",
                                     headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
        with opener.open(req, timeout=1) as response:
            token = response.read(4096).decode("ascii")
        def get(path):
            req = urllib.request.Request(base + path, headers={"X-aws-ec2-metadata-token": token})
            with opener.open(req, timeout=1) as response:
                return response.read(16384).decode("utf-8")
        doc = json.loads(get("dynamic/instance-identity/document"))
        try:
            doc["zone_id"] = get("meta-data/placement/availability-zone-id")
        except Exception:
            pass
        return doc
    except Exception:
        return {}


def run_check(requirements, expected_instance_id, metadata=None):
    deadline = time.monotonic() + 45
    issues = []
    def issue(code, remediation, blocking=True):
        issues.append({"code": code, "remediation": remediation, "blocking": blocking})
    doc = _metadata() if metadata is None else metadata
    instance_id = doc.get("instanceId")
    if not instance_id:
        try:
            with open("/sys/devices/virtual/dmi/id/board_asset_tag", encoding="ascii") as stream:
                candidate = stream.read(64).strip()
            if re.fullmatch(r"i-(?:[0-9a-f]{8}|[0-9a-f]{17})", candidate):
                instance_id = candidate
        except (OSError, UnicodeError):
            pass
    identity = {"hostname": socket.gethostname(), "instance_id": instance_id,
                "zone_id": doc.get("zone_id"), "availability_zone": doc.get("availabilityZone"),
                "region": doc.get("region"), "private_ip": doc.get("privateIp"),
                "identity_verified": instance_id == expected_instance_id,
                "source_verified": False,
                "source_note": "Host/IMDS addresses do not prove the source observed by Kafka after NAT."}
    if not identity["identity_verified"]:
        issue("target_identity_unverified", "Enable read-only EC2 IMDSv2 identity access or verify the target DMI instance identity; correct the runner target.")
    expected_zone = requirements.get("expected_zone_id")
    if expected_zone and identity["zone_id"] != expected_zone:
        issue("zone_mismatch_or_unverified", "Verify the real remote AZ ID and correct the case topology; do not substitute a client label.")
    elif not identity["zone_id"]:
        issue("zone_unverified", "For an AZ case, supply independently verified location evidence and check it in the case.", False)
    dependencies = {"python": {"version": platform.python_version(), "ok": sys.version_info >= (3, 9)},
                    "linux": {"ok": sys.platform.startswith("linux")}, "tools": {}}
    if not dependencies["python"]["ok"]:
        issue("python_missing", "Explicitly install Python 3.9+ on the remote client and rerun check.")
    if not dependencies["linux"]["ok"]:
        issue("linux_required", "Select an existing Linux SSM-managed client.")
    if requirements.get("java", True):
        java_home = os.environ.get("JAVA_HOME")
        java = os.path.join(java_home, "bin", "java") if java_home else shutil.which("java")
        major = None
        if java and os.path.isfile(java) and os.access(java, os.X_OK):
            try:
                response = subprocess.run([java, "-version"], capture_output=True, text=True, timeout=5)
                match = re.search(r'version\s+"(\d+)(?:\.(\d+))?', response.stderr + response.stdout)
                if response.returncode == 0 and match:
                    major = int(match.group(2) if match.group(1) == "1" else match.group(1))
            except (OSError, subprocess.TimeoutExpired):
                pass
        dependencies["java"] = {"ok": major is not None and major >= 17, "major": major}
        if not dependencies["java"]["ok"]:
            issue("java_missing_or_old", "Explicitly install Java 17+ remotely and correct JAVA_HOME/PATH; check does not install dependencies.")
    for name in requirements.get("tools", []):
        found = bool(shutil.which(name))
        dependencies["tools"][name] = {"ok": found}
        if not found:
            issue("tool_missing_" + name, "Explicitly install the required remote tool: " + name)
    permissions = {"capture_requested": requirements.get("capture", False), "capture_ok": None,
                   "effective_uid": os.geteuid() if hasattr(os, "geteuid") else None}
    path = requirements.get("remote_connection_file")
    if path:
        config = {"path": path, "ok": False, "restricted": False, "readable": False}
        try:
            info = os.lstat(path)
            config["restricted"] = stat.S_ISREG(info.st_mode) and not (stat.S_IMODE(info.st_mode) & 0o077)
            config["readable"] = os.access(path, os.R_OK)
            config["ok"] = config["restricted"] and config["readable"]
        except OSError:
            pass
        permissions["connection_file"] = config
        if not config["ok"]:
            issue("connection_file_unavailable_or_unrestricted", "Prepare a readable regular remote Kafka properties file with mode 0600 (no symlink); pass its absolute remote path. No credentials are uploaded.")
    if requirements.get("forbid_az_overrides", False):
        override = {"checked": False, "present": None}
        permissions["az_overrides"] = override
        try:
            if not permissions.get("connection_file", {}).get("ok"):
                raise ValueError()
            with open(path, "rb") as stream:
                data = stream.read(1024 * 1024 + 1)
            if len(data) > 1024 * 1024:
                raise ValueError()
            properties = _java_properties(data)
            override.update(checked=True, present="client.rack" in properties or "automq_az" in properties.get("client.id", ""))
            if override["present"]:
                issue("az_override_forbidden", "Use a dedicated case configuration without client.rack or a client.id automq_az override; no property values are displayed.")
        except (OSError, ValueError):
            issue("az_override_unverified", "Verify the restricted remote Java properties file and its escape syntax; AZ overrides could not be checked.")
    if requirements.get("capture", False):
        try:
            with socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)):
                pass
            permissions["capture_ok"] = True
        except (OSError, AttributeError):
            permissions["capture_ok"] = False
            issue("capture_permission_missing", "Have the authorized operator prepare case capture permissions; ordinary workload does not require capture. No IAM or host permissions are changed.")
    connectivity = []
    for endpoint in requirements.get("endpoints", []):
        result = dict(endpoint, ok=False, scope="TCP connect only; no Kafka authentication or source proof")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            issue("endpoint_not_checked", "The bounded check budget expired; rerun with fewer endpoints. An unchecked endpoint is not reachable evidence.")
            connectivity.append(result)
            continue
        try:
            _tcp_probe(endpoint["host"], endpoint["port"], timeout=min(2, remaining))
            result["ok"] = True
        except OSError:
            issue("endpoint_unreachable", "Verify private DNS, existing routes, security groups and Kafka listener access with the operator; check does not change networking.")
        connectivity.append(result)
    return {"schema_version": 1, "ok": not any(item["blocking"] for item in issues),
            "identity": identity, "dependencies": dependencies, "permissions": permissions,
            "connectivity": connectivity, "issues": issues}


def _java_properties(data):
    """Java Properties.load(InputStream) syntax, including escaped keys/lines.

    Only used for the explicitly requested AZ override check; parsed contents
    never leave this process or appear in diagnostics.
    """
    text = data.decode('iso-8859-1')
    logical, pending, continuing = [], '', False
    for line in text.replace('\r\n', '\n').replace('\r', '\n').split('\n'):
        line = line.lstrip(' \t\f')
        if not continuing and (not line or line.startswith(('#', '!'))):
            continue
        joined = pending + line
        count = len(joined) - len(joined.rstrip('\\'))
        if count % 2:
            pending = joined[:-1]
            continuing = True
        else:
            logical.append(joined)
            pending, continuing = '', False
    if continuing:
        logical.append(pending)
    def unescape(value):
        output, i = [], 0
        while i < len(value):
            if value[i] != '\\':
                output.append(value[i]); i += 1; continue
            i += 1
            if i == len(value):
                break
            escaped = value[i]; i += 1
            if escaped == 'u':
                digits = value[i:i+4]
                if len(digits) != 4 or not re.fullmatch('[0-9a-fA-F]{4}', digits):
                    raise ValueError('invalid properties escape')
                output.append(chr(int(digits, 16))); i += 4
            else:
                output.append({'t': '\t', 'r': '\r', 'n': '\n', 'f': '\f'}.get(escaped, escaped))
        return ''.join(output)
    result = {}
    for line in logical:
        line = line.lstrip(' \t\f')
        if not line or line.startswith(('#', '!')):
            continue
        escaped, end = False, len(line)
        for i, char in enumerate(line):
            if not escaped and char in '=:\t\f ':
                end = i; break
            if char == '\\':
                escaped = not escaped
            else:
                escaped = False
        tail = line[end:].lstrip(' \t\f')
        if tail.startswith(('=', ':')):
            tail = tail[1:].lstrip(' \t\f')
        result[unescape(line[:end])] = unescape(tail)
    return result
