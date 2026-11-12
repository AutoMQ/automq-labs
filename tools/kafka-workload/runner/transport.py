"""Short SSM commands with private, ephemeral JSON request files.

AWS CLI v2 file:// handling is not compatible with a piped /dev/stdin on
all supported hosts. Only a temporary path appears in argv, never the body.
"""
import json
import os
import subprocess
import tempfile
import time

from .schema import RunnerError, load_runner


class TransportError(RunnerError):
    pass


class AwsSsmTransport:
    def __init__(self, runner, execute=None, sleep=time.sleep, monotonic=time.monotonic, deadline=None):
        self.runner = load_runner(runner)
        self.execute = execute or subprocess.run
        self.sleep = sleep
        self.monotonic = monotonic
        self.deadline = deadline

    def remaining(self, limit):
        remaining = limit if self.deadline is None else min(limit, self.deadline - self.monotonic())
        if remaining <= 0:
            raise TransportError("Local operation deadline reached; remote status is unconfirmed")
        return remaining

    def request(self, service, operation, body, allow_not_found=False):
        argv = ["aws", "--region", self.runner.region, "--output", "json", "--no-cli-pager"]
        if self.runner.profile:
            argv += ["--profile", self.runner.profile]
        env = dict(os.environ, AWS_PAGER="", AWS_CLI_AUTO_PROMPT="off")
        try:
            with tempfile.TemporaryDirectory(prefix="automq-runner-request-") as directory:
                os.chmod(directory, 0o700)
                path = os.path.join(directory, "request.json")
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as stream:
                    json.dump(body, stream)
                argv += [service, operation, "--cli-input-json", "file://" + path]
                # TemporaryDirectory removes the private file in both success
                # and exception paths, after AWS CLI has finished reading it.
                completed = self.execute(argv, text=True, capture_output=True,
                                         timeout=self.remaining(40), env=env)
        except (OSError, subprocess.TimeoutExpired):
            raise TransportError("AWS CLI unavailable or timed out; verify local AWS CLI and authorized profile") from None
        if completed.returncode:
            if allow_not_found and "InvocationDoesNotExist" in (completed.stderr or ""):
                return None
            raise TransportError("AWS %s %s failed; verify profile authorization, region and target access" % (service, operation))
        try:
            value = json.loads(completed.stdout)
        except (TypeError, ValueError):
            raise TransportError("AWS CLI returned invalid JSON") from None
        if not isinstance(value, dict):
            raise TransportError("AWS CLI returned an invalid response")
        return value

    def caller_identity(self):
        result = self.request("sts", "get-caller-identity", {})
        if not all(isinstance(result.get(k), str) for k in ("Account", "Arn", "UserId")):
            raise TransportError("AWS STS returned incomplete identity")
        return {k: result[k] for k in ("Account", "Arn", "UserId")}

    def run(self, command, timeout_seconds=60):
        result = self.request("ssm", "send-command", {
            "DocumentName": "AWS-RunShellScript", "InstanceIds": [self.runner.instance_id],
            "TimeoutSeconds": 60,
            "Parameters": {"commands": [command], "executionTimeout": [str(timeout_seconds)]}})
        command_id = result.get("Command", {}).get("CommandId")
        if not command_id:
            raise TransportError("SSM did not return a command ID")
        deadline = self.monotonic() + timeout_seconds + 30
        if self.deadline is not None:
            deadline = min(deadline, self.deadline)
        while self.monotonic() < deadline:
            response = self.request("ssm", "get-command-invocation", {
                "CommandId": command_id, "InstanceId": self.runner.instance_id}, allow_not_found=True)
            if response is None or response.get("Status") in ("Pending", "InProgress", "Delayed"):
                self.sleep(min(1, self.remaining(1)))
                continue
            if response.get("Status") != "Success" or response.get("ResponseCode") != 0:
                raise TransportError("SSM command failed; verify target prerequisites and SSM authorization")
            output = response.get("StandardOutputContent", "")
            # SSM truncates inline stdout at 24,000 characters. Never treat a
            # partial envelope or an external output URL as a healthy frame.
            if not isinstance(output, str) or len(output.encode("utf-8")) >= 24000 or response.get("StandardOutputUrl"):
                raise TransportError("SSM output is truncated or external; snapshot unavailable")
            try:
                parsed = json.loads(output)
            except ValueError:
                raise TransportError("SSM returned no complete JSON envelope") from None
            if not isinstance(parsed, dict) or parsed.get("schema_version") != 1:
                raise TransportError("SSM returned an invalid envelope")
            return parsed
        raise TransportError("SSM response timed out; remote operation status is unconfirmed")
