"""Strict, secret-free v1 configuration shared by the controller and cases."""
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path, PurePosixPath


class RunnerError(Exception):
    """A safe diagnostic; never wrap raw subprocess stderr in this error."""


class ValidationError(RunnerError):
    pass


def identifier(value, name="identifier"):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
        raise ValidationError(name + " must match [A-Za-z0-9_-]{1,64}")
    return value


def absolute_path(value, name):
    if (not isinstance(value, str) or not value.startswith("/") or
            any(ord(c) < 32 for c in value) or ".." in value.split("/") or
            str(PurePosixPath(value)) == "/"):
        raise ValidationError(name + " must be an absolute remote file/directory path without '..'")
    return str(PurePosixPath(value))


def bounded_number(value, name, low, high, integer=False):
    import math
    if (isinstance(value, bool) or not isinstance(value, (int, float)) or
            not math.isfinite(value) or not low <= value <= high or
            (integer and not isinstance(value, int))):
        raise ValidationError("%s must be %s..%s" % (name, low, high))
    return value


@dataclass(frozen=True)
class RunnerConfig:
    region: str
    instance_id: str
    remote_root: str
    profile: str = None
    schema_version: int = 1
    transport: str = "ssm"
    poll_seconds: float = 3
    lease_seconds: int = 90
    max_runtime_seconds: int = 900

    def __post_init__(self):
        if type(self.schema_version) is not int or self.schema_version != 1:
            raise ValidationError("runner schema_version must be 1")
        if self.transport != "ssm":
            raise ValidationError("only the ssm transport is supported")
        if not isinstance(self.region, str) or not re.fullmatch(r"[a-z]{2}(?:-[a-z]+)+-\d+", self.region):
            raise ValidationError("region must be an AWS region name")
        if not isinstance(self.instance_id, str) or not re.fullmatch(r"i-(?:[0-9a-f]{8}|[0-9a-f]{17})", self.instance_id):
            raise ValidationError("instance_id must be an EC2 instance ID")
        if self.profile is not None and (not isinstance(self.profile, str) or
                not re.fullmatch(r"[A-Za-z0-9_.@-]{1,128}", self.profile)):
            raise ValidationError("profile must be a local AWS profile name")
        object.__setattr__(self, "remote_root", absolute_path(self.remote_root, "remote_root"))
        bounded_number(self.poll_seconds, "poll_seconds", 1, 15)
        bounded_number(self.lease_seconds, "lease_seconds", 15, 90, integer=True)
        bounded_number(self.max_runtime_seconds, "max_runtime_seconds", 1, 900, integer=True)

    def as_dict(self):
        return asdict(self)


def load_runner(value):
    if isinstance(value, RunnerConfig):
        return value
    if isinstance(value, (str, Path)):
        try:
            with open(value, encoding="utf-8") as stream:
                value = json.load(stream)
        except (OSError, ValueError):
            raise ValidationError("cannot read runner JSON file") from None
    if not isinstance(value, dict):
        raise ValidationError("runner must be a config mapping or a local JSON file path")
    allowed = set(RunnerConfig.__dataclass_fields__)
    if set(value) - allowed:
        raise ValidationError("unknown runner fields: " + ", ".join(sorted(set(value) - allowed)))
    try:
        return RunnerConfig(**value)
    except TypeError:
        raise ValidationError("runner requires region, instance_id and remote_root") from None


def check_requirements(value=None):
    value = {} if value is None else value
    allowed = {"remote_connection_file", "endpoints", "expected_zone_id", "tools", "capture", "java", "forbid_az_overrides"}
    if not isinstance(value, dict) or set(value) - allowed:
        raise ValidationError("unsupported check requirements")
    result = {"endpoints": [], "tools": [], "capture": False, "java": True, "forbid_az_overrides": False}
    result.update(value)
    for flag in ("capture", "java", "forbid_az_overrides"):
        if not isinstance(result[flag], bool):
            raise ValidationError(flag + " must be boolean")
    if "remote_connection_file" in result:
        result["remote_connection_file"] = absolute_path(result["remote_connection_file"], "remote_connection_file")
    if "expected_zone_id" in result:
        if not isinstance(result["expected_zone_id"], str) or not re.fullmatch(r"[a-z0-9-]{1,64}", result["expected_zone_id"]):
            raise ValidationError("expected_zone_id must be an AWS AZ ID")
    if not isinstance(result["tools"], list) or len(result["tools"]) > 20:
        raise ValidationError("tools must be a list of at most 20 executable names")
    for tool in result["tools"]:
        if not isinstance(tool, str) or not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", tool):
            raise ValidationError("tools must contain executable names, not commands")
    if not isinstance(result["endpoints"], list) or len(result["endpoints"]) > 100:
        raise ValidationError("endpoints must be a list of at most 100 Kafka endpoints")
    for endpoint in result["endpoints"]:
        if not isinstance(endpoint, dict) or set(endpoint) != {"host", "port"}:
            raise ValidationError("each endpoint requires host and port")
        host = endpoint["host"]
        if not isinstance(host, str) or not re.fullmatch(r"[A-Za-z0-9_.:-]{1,253}", host):
            raise ValidationError("invalid endpoint host")
        bounded_number(endpoint["port"], "endpoint port", 1, 65535, integer=True)
    if result['forbid_az_overrides'] and 'remote_connection_file' not in result:
        raise ValidationError('AZ override checks require remote_connection_file')
    return result


def task_descriptor(value, runner=None):
    if not isinstance(value, dict):
        raise ValidationError('task descriptor must be an object')
    allowed = {'schema_version', 'task_id', 'controller_id', 'role', 'run_id', 'phase', 'argv',
               'scope_id', 'lease_seconds', 'max_runtime_seconds'}
    if set(value) - allowed or value.get('schema_version') != 1:
        raise ValidationError('invalid task descriptor schema or fields')
    result = dict(value)
    for key in ('task_id', 'controller_id', 'run_id', 'phase'):
        identifier(result.get(key), key)
    if result.get('role') not in ('topic', 'produce', 'consume', 'watch', 'scope-prepare', 'scope-cleanup'):
        raise ValidationError('unsupported task role')
    if result.get('scope_id') is not None:
        identifier(result['scope_id'], 'scope_id')
    if result['role'].startswith('scope-') and result.get('scope_id') is not None:
        raise ValidationError('scope helper must not claim its own scope as an active task')
    argv = result.get('argv')
    if (not isinstance(argv, list) or not 1 <= len(argv) <= 100 or
            any(not isinstance(a, str) or len(a) > 16384 or '\x00' in a for a in argv) or
            sum(len(a) for a in argv) > 24000):
        raise ValidationError('task argv must be a bounded string vector')
    result.setdefault('lease_seconds', runner.lease_seconds if runner else 90)
    result.setdefault('max_runtime_seconds', runner.max_runtime_seconds if runner else 900)
    bounded_number(result['lease_seconds'], 'lease_seconds', 15, 90, integer=True)
    bounded_number(result['max_runtime_seconds'], 'max_runtime_seconds', 1, 900, integer=True)
    return result
