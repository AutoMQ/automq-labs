import ast
import base64
import json
import os
from pathlib import Path
import re
import socket
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from runner import RunnerConfig, ValidationError, check, load_runner
from runner.preflight import _tcp_probe, run_check
from runner.schema import check_requirements
from runner.transport import AwsSsmTransport, TransportError


CONFIG = {"schema_version": 1, "transport": "ssm", "region": "us-east-1",
          "instance_id": "i-0123456789abcdef0", "profile": "test-profile",
          "remote_root": "/opt/automq-labs/client-case"}
METADATA = {"instanceId": CONFIG["instance_id"], "region": "us-east-1", "privateIp": "10.0.1.5"}


class ConfigTests(unittest.TestCase):
    def test_reject_unknown_secret_or_transport_fields(self):
        for fields in ({"password": "secret"}, {"transport": "ssh"}, {"instance_id": "i-x;touch /tmp/x"}):
            with self.subTest(fields=list(fields)), self.assertRaises(ValidationError):
                load_runner(dict(CONFIG, **fields))

    def test_explicit_bounds_prevent_unbounded_tasks(self):
        for fields in ({"lease_seconds": 91}, {"lease_seconds": True}, {"max_runtime_seconds": 901},
                       {"poll_seconds": float("nan")}, {"remote_root": "/"}, {"remote_root": "/opt/../etc"}):
            with self.subTest(fields=fields), self.assertRaises(ValidationError):
                load_runner(dict(CONFIG, **fields))

    def test_local_json_config_does_not_depend_on_cwd(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "runner.json"
            path.write_text(json.dumps(CONFIG))
            config = load_runner(path)
            self.assertIsInstance(config, RunnerConfig)
            self.assertEqual(config.lease_seconds, 90)
            self.assertEqual(config.max_runtime_seconds, 900)

    def test_requirements_validate_remote_paths_and_command_inputs(self):
        invalid = [{"remote_connection_file": "./local.properties"}, {"remote_connection_file": "/tmp/../secret"},
                   {"tools": ["ip;id"]}, {"capture": "yes"}, {"endpoints": [{"host": "x", "port": True}]},
                   {"endpoints": [{"host": "x\nsh", "port": 9092}]}, {"java": 1}]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(ValidationError):
                check_requirements(value)


class PreflightTests(unittest.TestCase):
    def run_remote_check(self, requirements=None, metadata=None):
        defaults = {"java": False, "capture": False, "tools": [], "endpoints": []}
        defaults.update(requirements or {})
        with patch("runner.preflight.sys.platform", "linux"):
            return run_check(defaults, CONFIG["instance_id"], METADATA if metadata is None else metadata)

    def test_ordinary_workload_does_not_require_az_or_capture(self):
        with patch("runner.preflight.socket.socket", side_effect=AssertionError("must not capture")):
            result = self.run_remote_check()
        self.assertTrue(result["ok"])
        self.assertFalse(result["identity"]["source_verified"])
        self.assertIsNone(result["permissions"]["capture_ok"])
        self.assertEqual(result["issues"][0]["code"], "zone_unverified")
        self.assertFalse(result["issues"][0]["blocking"])

    def test_actual_target_mismatch_blocks(self):
        result = self.run_remote_check(metadata=dict(METADATA, instanceId="i-aaaaaaaa"))
        self.assertFalse(result["ok"])
        self.assertFalse(result["identity"]["identity_verified"])

    def test_expected_zone_is_an_explicit_case_gate(self):
        self.assertFalse(self.run_remote_check({"expected_zone_id": "use1-az1"})["ok"])
        self.assertTrue(self.run_remote_check({"expected_zone_id": "use1-az1"}, dict(METADATA, zone_id="use1-az1"))["ok"])

    def test_config_is_stat_only_never_opened_or_printed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "client.properties"
            path.write_text("sasl.jaas.config=SECRET_DO_NOT_READ")
            path.chmod(0o600)
            with patch("builtins.open", side_effect=AssertionError("must not read properties")):
                result = self.run_remote_check({"remote_connection_file": str(path)})
            self.assertTrue(result["ok"])
            self.assertNotIn("SECRET_DO_NOT_READ", json.dumps(result))
            path.chmod(0o644)
            self.assertFalse(self.run_remote_check({"remote_connection_file": str(path)})["ok"])
            link = Path(directory) / "link"
            link.symlink_to(path)
            self.assertFalse(self.run_remote_check({"remote_connection_file": str(link)})["ok"])

    def test_tcp_probe_reports_failures_without_kafka_payload(self):
        connection = unittest.mock.MagicMock()
        with patch("runner.preflight._resolve_addresses", return_value=[(socket.AF_INET, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", ("10.0.0.1", 9092))]), \
                patch("runner.preflight.socket.socket", return_value=connection):
            result = self.run_remote_check({"endpoints": [{"host": "private.example", "port": 9092}]})
        connection.__enter__.return_value.connect.assert_called_once_with(("10.0.0.1", 9092))
        self.assertTrue(result["connectivity"][0]["ok"])
        connection.send.assert_not_called()
        connection.__enter__.return_value.send.assert_not_called()
        with patch("runner.preflight._tcp_probe", side_effect=OSError("SECRET")):
            result = self.run_remote_check({"endpoints": [{"host": "private.example", "port": 9092}]})
        self.assertFalse(result["ok"])
        self.assertNotIn("SECRET", json.dumps(result))

    def test_slow_dns_is_killed_and_reaped_within_probe_budget(self):
        # Exercise real subprocess timeout behavior, not a fake resolver error.
        processes = []
        real_popen = subprocess.Popen
        def record_process(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            processes.append(process)
            return process
        started = time.monotonic()
        with patch("runner.preflight._RESOLVE_CODE", "import time; time.sleep(10)"), \
                patch("subprocess.Popen", side_effect=record_process), \
                self.assertRaises(OSError):
            _tcp_probe("slow.example", 9092, timeout=0.1)
        self.assertLess(time.monotonic() - started, 2)
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].poll())

    def test_numeric_ip_does_not_start_dns_process(self):
        connection = unittest.mock.MagicMock()
        with patch("runner.preflight.subprocess.run", side_effect=AssertionError("must not resolve numeric IP")), \
                patch("runner.preflight.socket.socket", return_value=connection):
            _tcp_probe("10.0.0.1", 9092, timeout=1)
        connection.__enter__.return_value.connect.assert_called_once_with(("10.0.0.1", 9092))

    def test_capture_failure_is_explicit_and_never_zero(self):
        with patch("runner.preflight.socket.socket", side_effect=PermissionError("SECRET")):
            result = self.run_remote_check({"capture": True})
        self.assertFalse(result["ok"])
        self.assertFalse(result["permissions"]["capture_ok"])

    def test_java_version_is_checked_and_raw_stderr_is_not_returned(self):
        for version, ok in (("17.0.8", True), ("11.0.1", False)):
            with patch.dict(os.environ, {"JAVA_HOME": "/fake/jdk"}), \
                    patch("runner.preflight.os.path.isfile", return_value=True), \
                    patch("runner.preflight.os.access", return_value=True), \
                    patch("runner.preflight.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "", 'openjdk version "%s" SECRET' % version)):
                result = self.run_remote_check({"java": True})
            self.assertEqual(result["ok"], ok)
            self.assertNotIn("SECRET", json.dumps(result))


class TransportTests(unittest.TestCase):
    def transport(self, responses):
        calls = []
        def execute(argv, **kwargs):
            request_path = Path(argv[argv.index("--cli-input-json") + 1][len("file://"):])
            # Inspect the real file while the CLI would be reading it.
            details = dict(kwargs, body=json.loads(request_path.read_text()), request_path=request_path,
                           file_mode=stat.S_IMODE(request_path.stat().st_mode),
                           directory_mode=stat.S_IMODE(request_path.parent.stat().st_mode))
            calls.append((argv, details))
            value = responses.pop(0)
            if isinstance(value, tuple):
                return subprocess.CompletedProcess(argv, value[0], "", value[1])
            return subprocess.CompletedProcess(argv, 0, json.dumps(value), "")
        return AwsSsmTransport(CONFIG, execute=execute, sleep=lambda _: None), calls

    def test_api_inputs_use_private_ephemeral_json_and_not_argv(self):
        transport, calls = self.transport([{"Account": "1", "Arn": "arn:test", "UserId": "id"}])
        transport.caller_identity()
        argv, kwargs = calls[0]
        self.assertEqual(kwargs["body"], {})
        self.assertEqual(kwargs["file_mode"], 0o600)
        self.assertEqual(kwargs["directory_mode"], 0o700)
        self.assertFalse(kwargs["request_path"].exists())
        self.assertFalse(kwargs["request_path"].parent.exists())
        self.assertEqual(kwargs["env"]["AWS_CLI_AUTO_PROMPT"], "off")

    def test_request_file_removed_when_cli_raises(self):
        for exception in (OSError("SECRET"), subprocess.TimeoutExpired("aws", 40), KeyboardInterrupt()):
            paths = []
            def execute(argv, **kwargs):
                path = Path(argv[argv.index("--cli-input-json") + 1][len("file://"):])
                paths.append(path)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                self.assertEqual(json.loads(path.read_text()), {"safe": "body-not-in-argv"})
                self.assertNotIn("body-not-in-argv", " ".join(argv))
                raise exception
            transport = AwsSsmTransport(CONFIG, execute=execute)
            with self.assertRaises((TransportError, KeyboardInterrupt)):
                transport.request("sts", "get-caller-identity", {"safe": "body-not-in-argv"})
            self.assertFalse(paths[0].exists())
            self.assertFalse(paths[0].parent.exists())

    def test_short_command_eventual_consistency_then_complete_json(self):
        transport, calls = self.transport([{"Command": {"CommandId": "id"}}, (1, "InvocationDoesNotExist"),
            {"Status": "InProgress"}, {"Status": "Success", "ResponseCode": 0,
                                       "StandardOutputContent": '{"schema_version":1,"ok":true}'}])
        self.assertTrue(transport.run("do-not-put-in-argv")["ok"])
        self.assertEqual(len(calls), 4)
        self.assertNotIn("do-not-put-in-argv", " ".join(calls[0][0]))
        self.assertEqual(calls[0][1]["body"]["Parameters"]["commands"], ["do-not-put-in-argv"])

    def test_truncated_or_missing_output_cannot_be_healthy(self):
        for output in ("", '{"schema_version":1', "x" * 24000):
            transport, _ = self.transport([{"Command": {"CommandId": "id"}},
                {"Status": "Success", "ResponseCode": 0, "StandardOutputContent": output}])
            with self.assertRaises(TransportError):
                transport.run("check")

    def test_raw_aws_error_is_never_exposed(self):
        transport, _ = self.transport([(1, "AccessDenied SECRET")])
        with self.assertRaises(TransportError) as context:
            transport.caller_identity()
        self.assertNotIn("SECRET", str(context.exception))

    def test_check_transmits_bootstrap_but_no_properties_contents(self):
        class FakeTransport:
            def caller_identity(self):
                return {"Arn": "test"}
            def run(self, command, timeout_seconds):
                encoded = re.search(r"b64decode\('([^']+)'\)", command).group(1)
                source = base64.b64decode(encoded).decode()
                self.assert_source = source
                ast.parse(source, feature_version=(3, 9))
                return {"schema_version": 1, "ok": True, "identity": {"instance_id": CONFIG["instance_id"]}, "issues": []}
        transport = FakeTransport()
        result = check(CONFIG, {"remote_connection_file": "/opt/private.properties"}, transport=transport)
        self.assertTrue(result["ok"])
        self.assertEqual(result["target"]["transport"], "ssm")
        self.assertIn("run_check", transport.assert_source)

    def test_package_syntax_is_python39_compatible(self):
        for path in Path(__file__).resolve().parents[1].glob("*.py"):
            ast.parse(path.read_text(), filename=str(path), feature_version=(3, 9))


if __name__ == "__main__":
    unittest.main()
