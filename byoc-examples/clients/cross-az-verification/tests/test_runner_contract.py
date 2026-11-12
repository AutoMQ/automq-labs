"""Public runner APIs with a fake SSM boundary; no root, cloud or Kafka.

The fixture models trusted root-owned scope metadata only while checking argv.
All packet/OS lifecycle validation remains a separate real-Linux E2E gate.
"""
import base64
import contextlib
import copy
import hashlib
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from cross_az import cli, demo
from cross_az.collector import RetainedWindow, WorkloadReader
from cross_az.config import CaseError, load
from cross_az.view import compare, observation, render

CASE_ROOT = pathlib.Path(__file__).resolve().parents[1]
WORKLOAD_ROOT = CASE_ROOT.parents[2] / "tools" / "kafka-workload"
sys.path.insert(0, str(WORKLOAD_ROOT))
from runner import api
from runner.bundle import build_bundle
from runner.installer import install_archive
from runner.remote_agent import trusted_argv
from runner.schema import ValidationError
from runner.transport import TransportError


class FakeSsmBoundary:
    def __init__(self, case, releases):
        self.case, self.releases = case, releases
        self.tasks, self.calls, self.specs = {}, [], {}
        self.end_offsets = {case["topic"] + ":" + str(p): 100 for p in range(case["workload"]["partitions"])}
        self.break_task = None
        self.fail_scope = False
        self.lose_start_ack = False
        self.query_clock = None
        self.snapshot_delay = 0
        self.related_queries = 0
        self.finish_watch_after_queries = None
        self.unconfirm_watch_stop = False

    def transport(self, config, deadline=None):
        outer = self
        client = next(name for name, value in self.case["clients"].items() if json.loads(pathlib.Path(value["runner_file"]).read_text())["instance_id"] == config.instance_id)
        class Transport:
            def caller_identity(self):
                return {"Account": "000000000000", "Arn": "fixture"}
            def run(self, command, timeout_seconds):
                return outer.run(config, client, command)
        return Transport()

    def identity(self, client):
        value = self.case["clients"][client]
        config = json.loads(pathlib.Path(value["runner_file"]).read_text())
        return {"instance_id": config["instance_id"], "hostname": "fixture-" + client,
                "private_ip": value["source_ip"], "zone_id": value["zone_id"], "identity_verified": True}

    def validate_trusted(self, root, descriptor):
        original = pathlib.Path.lstat
        scopes = pathlib.Path(root) / "state" / "scopes"
        def modeled_root_ownership(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            if path == scopes or path.parent == scopes:
                fields = list(info)
                fields[4] = 0  # stat tuple uid; fixture only, never chmod/chown OS resources.
                return os.stat_result(fields)
            return info
        with patch.object(pathlib.Path, "lstat", modeled_root_ownership), patch("runner.remote_agent.read_json", lambda path: json.loads(pathlib.Path(path).read_text())):
            return trusted_argv(pathlib.Path(root), self.releases[root], descriptor)

    def run(self, config, client, command):
        if "-m runner.remote_agent" not in command:
            encoded = re.search(r"b64decode\('([^']+)'\)", command).group(1)
            source = base64.b64decode(encoded).decode()
            nested = re.search(r"_r, _i = json.loads\(base64.b64decode\('([^']+)'\)\)", source).group(1)
            requirements, instance = json.loads(base64.b64decode(nested))
            assert requirements["forbid_az_overrides"] is True
            assert instance == config.instance_id
            self.calls.append(("check", client, requirements))
            return {"schema_version": 1, "ok": True, "identity": self.identity(client), "dependencies": {},
                    "permissions": {"az_overrides": {"checked": True, "present": False}}, "connectivity": [], "issues": []}
        tokens = shlex.split(command)
        operation = tokens[tokens.index("runner.remote_agent") + 1]
        request = json.loads(base64.b64decode(tokens[tokens.index("--request-b64") + 1]))
        self.calls.append((operation, client, copy.deepcopy(request)))
        if operation == "start":
            descriptor = request["descriptor"]
            task = descriptor["task_id"]
            if task in self.tasks:
                raise AssertionError("case must not start a role twice")
            argv = self.validate_trusted(config.remote_root, descriptor)
            role = descriptor["role"]
            state = {"schema_version": 1, "task_id": task, "controller_id": descriptor["controller_id"],
                     "role": role, "state": "running", "stop_confirmed": False, "frame_age_ms": 0,
                     "frame_seq": 1, "last_frame": None, "identity": self.identity(client), "exit_code": None}
            if role.startswith("scope-"):
                spec = json.loads(descriptor["argv"][-1])
                self.specs[(client, descriptor["phase"])] = spec
                scopes = pathlib.Path(config.remote_root) / "state" / "scopes"
                scopes.mkdir(parents=True, exist_ok=True, mode=0o700)
                ledger = {"owner": spec["scope_id"], "namespace": "az-" + hashlib.sha256(spec["scope_id"].encode()).hexdigest()[:10],
                          "state": "prepared", "source_proof": {"verified": not self.fail_scope}}
                path = scopes / (spec["scope_id"] + ".json")
                path.write_text(json.dumps(ledger))
                path.chmod(0o600)
                state.update(state="failed" if self.fail_scope else "stopped", stop_confirmed=True, exit_code=2 if self.fail_scope else 0,
                             last_frame={"schema_version": 1, "event": "scope", "result": ledger})
            elif role == "consume":
                run_id = descriptor["argv"][descriptor["argv"].index("--run-id") + 1]
                ready = {"schema_version": 1, "event": "ready", "role": role, "run_id": run_id,
                         "start_offsets": dict(self.end_offsets), "sample_seq": 1, "messages": 0, "payload_bytes": 0, "state": "ready"}
                state.update(state="ready", last_frame=ready, ready_frame=ready)
            state["descriptor"] = descriptor
            state["resolved_argv"] = argv
            self.tasks[task] = state
            if self.lose_start_ack:
                raise TransportError("fixture acknowledgement lost after start")
            return copy.deepcopy(state)
        task = request["task_id"]
        if task == self.break_task:
            raise TransportError("fixture management disconnection")
        state = self.tasks[task]
        if operation == "snapshot" and state["role"] in ("produce", "consume") and self.query_clock is not None:
            self.query_clock[0] += self.snapshot_delay
            self.related_queries += 1
            if self.finish_watch_after_queries and self.related_queries >= 2:
                self.tasks[self.finish_watch_after_queries].update(state="stopped", stop_confirmed=True, exit_code=0)
        if request.get("renew"):
            assert request.get("controller_id") == state["controller_id"]
        if operation == "stop":
            assert request["controller_id"] == state["controller_id"]
            if self.unconfirm_watch_stop and state["role"] == "watch":
                raise TransportError("fixture watch stop acknowledgement unavailable")
            state.update(state="stopped", stop_confirmed=True, exit_code=143, application_exit_code=0)
            if state.get("last_frame") and state["role"] in ("consume", "produce"):
                state["last_frame"].update(event="final", exit_code=0, state="stopped")
        return copy.deepcopy(state)

    def drive(self, phase, cross_bytes):
        starts = dict(self.end_offsets)
        partitions = self.case["workload"]["partitions"]
        for client in self.case["clients"]:
            task = cli.task_id(self.case, client, phase, "produce")
            producer = self.tasks[task]
            ack = {}
            for p in range(partitions):
                key = self.case["topic"] + ":" + str(p)
                count = 600 // partitions + (p < 600 % partitions)
                self.end_offsets[key] += count
                ack[key] = self.end_offsets[key] - 1
            producer.update(state="stopped", stop_confirmed=True, exit_code=0, application_exit_code=0, frame_seq=5)
            producer["last_frame"] = {"schema_version": 1, "event": "final", "role": "produce", "run_id": cli.phase_run_id(self.case, phase),
                                      "sample_seq": 5, "messages": 600, "payload_bytes": 614400, "errors": 0, "exit_code": 0,
                                      "unconfirmed_messages": 0, "max_acked_offsets": ack}
        for client in self.case["clients"]:
            consumer = self.tasks[cli.task_id(self.case, client, phase, "consume")]
            consumer.update(state="running", frame_seq=5)
            consumer["last_frame"] = {"schema_version": 1, "event": "progress", "state": "running", "role": "consume", "run_id": cli.phase_run_id(self.case, phase),
                                      "sample_seq": 5, "messages": 1800, "payload_bytes": 1843200, "errors": 0, "next_offsets": dict(self.end_offsets)}
            frame = self.business_frame(client, phase, cross_bytes)
            retained = RetainedWindow(10).update(frame)
            frame["retained_window"] = retained
            # The live final window is idle; the historical business window
            # and its original time must survive the user's later drain.
            frame["sample_time"] = "2026-11-10T10:02:00Z"
            frame["window"] = {relation: {"tx_bytes": 0, "rx_bytes": 0} for relation in ("same", "cross", "unknown")}
            frame["workload"] = {"produce_active": False, "consume_active": False, "frames_fresh": True}
            watch = self.tasks[cli.task_id(self.case, client, phase, "watch")]
            watch.update(last_frame=frame, frame_seq=5)
        return starts, dict(self.end_offsets)

    def business_frame(self, client, phase, cross_bytes):
        spec = self.specs[(client, phase)]
        return {"schema_version": 1, "event": "network", "run_id": self.case["run_id"], "client_id": client,
                "phase": phase, "sample_seq": 4, "sample_time": "2026-11-10T10:00:00Z", "elapsed_seconds": 60,
                "window_seconds": 10, "scope_id": spec["scope_id"], "actual_zone_id": spec["zone_id"],
                "actual_hostname": spec["actual_hostname"], "actual_instance_id": spec["actual_instance_id"], "source_ip": spec["source_ip"],
                "quality": {"complete": True, "source_verified": True, "scope_intact": True, "kernel_drops": 0, "parse_errors": 0},
                "window": {"same": {"tx_bytes": 1200, "rx_bytes": 2400}, "cross": {"tx_bytes": cross_bytes, "rx_bytes": 0}, "unknown": {"tx_bytes": 0, "rx_bytes": 0}},
                "totals": {}, "peers": [], "workload_task_ids": spec["workload_task_ids"],
                "workload": {"produce_active": True, "consume_active": True, "produce_running": True, "consume_running": True, "frames_fresh": True,
                             "window_success": {"produce": {"messages": 90, "payload_bytes": 92160, "covered_seconds": 9}, "consume": {"messages": 270, "payload_bytes": 276480, "covered_seconds": 9}}}}


class PublicRunnerContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name).resolve()
        source = self.root / "bundle-source"
        (source / "target").mkdir(parents=True)
        (source / "workload").write_text("#!/bin/sh\nexit 0\n")
        (source / "target/workload.jar").write_bytes(b"fixture; no Java or Kafka execution")
        shutil.copytree(WORKLOAD_ROOT / "runner", source / "runner", ignore=shutil.ignore_patterns("__pycache__", "tests"))
        artifact = self.root / "runtime.tar"
        bundle = build_bundle(artifact, source, CASE_ROOT)
        value = json.loads((CASE_ROOT / "examples/case.json").read_text())
        value["run_id"] = "x" * 64
        value["clients"] = {}
        releases = {}
        for number, client in enumerate(("a", "b", "c"), start=1):
            remote = self.root / ("remote-" + client)
            release = pathlib.Path(install_archive(remote, artifact, bundle["sha256"])["release"])
            releases[str(remote)] = release
            properties = remote / "client.properties"
            properties.write_text("bootstrap.servers=private:9092\n")
            properties.chmod(0o600)
            runner = self.root / ("runner-" + client + ".json")
            runner.write_text(json.dumps({"schema_version": 1, "transport": "ssm", "region": "us-east-1", "instance_id": "i-" + str(number) * 17, "remote_root": str(remote), "poll_seconds": 1}))
            value["clients"][client] = {"runner_file": runner.name, "remote_connection_file": str(properties), "zone_id": "example-az" + str(number),
                                         "source_ip": "10.40." + str(number) + ".10", "source_cidrs": ["10.40." + str(number) + ".0/24"], "scope_cidr": "198.18.240.0/24"}
        self.config = self.root / "case.json"
        self.config.write_text(json.dumps(value))
        self.case = load(self.config)
        self.boundary = FakeSsmBoundary(self.case, releases)
        self.transport_patch = patch.object(api, "AwsSsmTransport", side_effect=self.boundary.transport)
        self.transport_patch.start()

    def tearDown(self):
        self.transport_patch.stop()
        self.temp.cleanup()

    def controller(self, client, phase="before"):
        args = SimpleNamespace(client=client, phase=phase, state_dir=str(self.root / "generated/state"), cohort="a,b,c", json=False, config=str(self.config))
        return cli.Controller(self.case, args, api)

    def prepare_phase(self, phase):
        controllers = [self.controller(c, phase) for c in self.case["clients"]]
        # Starting each role is still an explicit user operation. Only attach's
        # foreground waiting is suppressed here to model independent terminals.
        for controller in controllers:
            controller.check()
            with patch.object(controller, "attach", return_value=None), contextlib.redirect_stderr(io.StringIO()):
                controller.scoped("scope-prepare")
                controller.scoped("watch")
                controller.scoped("consume")
        return controllers

    def test_demo_emitted_roles_pass_installed_remote_trusted_argv_contract(self):
        # This uses the real public API, installed manifest validation and
        # remote_agent.trusted_argv. Only SSM/process execution is simulated.
        store = demo.Store(self.root / 'demo-state')
        directory = demo.begin(store, self.config, None, 'before', api)
        run = demo.Round(store, directory, 'before', api, output=lambda text: None)
        for client in run.cohort:
            run.controllers[client].check()
        run.submit('a', 'topic')
        for role in ('scope-prepare', 'watch', 'consume', 'produce'):
            for client in run.cohort:
                run.submit(client, role)
        # Scope cleanup has the same exact trusted entry, after all prior
        # mutable tasks have been explicitly stopped and journaled.
        for key, job in run.phase_state()['jobs'].items():
            descriptor = job['descriptor']
            stopped = api.stop(job['runner'], descriptor['task_id'], descriptor['controller_id'])
            self.assertTrue(stopped['stop_confirmed'])
            store.update(directory, lambda state, key=key: state['phases']['before']['jobs'][key].update(stop_confirmed=True))
        for client in run.cohort:
            run.submit(client, 'scope-cleanup', maintenance=True)
        seen = set()
        for job in run.phase_state()['jobs'].values():
            descriptor = job['descriptor']
            role = descriptor['role']
            root = job['runner']['remote_root']
            with self.subTest(role=role, client=job['client']):
                resolved = self.boundary.validate_trusted(root, descriptor)
                seen.add(role)
                if role == 'topic':
                    self.assertEqual(['./workload', 'topic', 'create'], descriptor['argv'][:3])
                    self.assertEqual(str(self.boundary.releases[root] / 'workload'), resolved[0])
                    broken = copy.deepcopy(descriptor)
                    broken['argv'] = broken['argv'][1:]
                    with self.assertRaisesRegex(ValidationError, 'installed release entry'):
                        self.boundary.validate_trusted(root, broken)
                elif role in ('produce', 'consume'):
                    self.assertEqual(['ip', 'netns', 'exec'], resolved[:3])
                    self.assertEqual(str(self.boundary.releases[root] / 'workload'), resolved[4])
                    self.assertEqual(role, resolved[5])
                else:
                    self.assertEqual(sys.executable, resolved[0])
                    self.assertEqual(['-m', 'cross_az.collector' if role == 'watch' else 'cross_az.scope'], resolved[1:3])
                unsupported = copy.deepcopy(descriptor)
                unsupported['argv'] += ['--unsupported', 'value']
                with self.assertRaises(ValidationError):
                    self.boundary.validate_trusted(root, unsupported)
        self.assertEqual({'topic', 'scope-prepare', 'watch', 'consume', 'produce', 'scope-cleanup'}, seen)

    def test_three_az_manual_before_drain_snapshot_after_via_public_api(self):
        result = subprocess.run([str(CASE_ROOT / "az-case"), "prepare", "--config", str(self.config), "--out", str(self.root / "generated")], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, result.stderr)
        topic = shlex.split((self.root / "generated/topic-create.sh").read_text().split("exec ", 1)[1])
        self.assertEqual(str(self.root / "generated/state"), topic[topic.index("--state-dir") + 1])
        self.assertLess(topic.index("--state-dir"), topic.index("start"))
        before = self.prepare_phase("before")
        for controller in before:
            with patch.object(controller, "attach", return_value=None):
                controller.scoped("produce")
        starts_before, targets_before = self.boundary.drive("before", 41)
        for controller in before:
            frame = self.boundary.tasks[cli.task_id(self.case, controller.args.client, "before", "watch")]["last_frame"]
            evidence = controller.evidence(copy.deepcopy(frame["retained_window"]))
            self.assertTrue(evidence["drained"])
            self.assertEqual(targets_before, evidence["target_next_offsets"])
            self.assertEqual(1800, evidence["successful_messages"])
            with contextlib.redirect_stdout(io.StringIO()):
                cli.main(["snapshot", "--config", str(self.config), "--client", controller.args.client, "--cohort", "a,b,c", "--state-dir", str(self.root / "generated/state")], api=api)
            baseline = controller.read(controller.args.client, "before", "baseline")
            self.assertEqual(41, baseline["window"]["cross"]["tx_bytes"])
            self.assertEqual("2026-11-10T10:00:00Z", baseline["sample_time"])
            # Watch status is read-only and never renews consumer/producer.
            for role in ("consume", "watch"):
                descriptor = controller.read(controller.args.client, "before", role)
                api.stop(controller.runner(controller.args.client), descriptor["task_id"], descriptor["controller_id"])
        after = self.prepare_phase("after")
        for controller in after:
            ready = controller.snapshot(controller.args.client, "after", "consume")["ready_frame"]
            self.assertEqual(targets_before, ready["start_offsets"])
            self.assertNotEqual(starts_before, ready["start_offsets"])
            with patch.object(controller, "attach", return_value=None):
                controller.scoped("produce")
        _, targets_after = self.boundary.drive("after", 0)
        for controller in after:
            frame = self.boundary.tasks[cli.task_id(self.case, controller.args.client, "after", "watch")]["last_frame"]
            retained = controller.evidence(frame["retained_window"])
            baseline = controller.read(controller.args.client, "before", "baseline")
            self.assertTrue(compare(baseline, retained)["comparable"])
            self.assertEqual(targets_after, retained["target_next_offsets"])
            output = render(frame, 0, frame["workload"], baseline=baseline)
            self.assertIn("fixture-", output)
            self.assertIn("HISTORICAL before", output)
            self.assertIn("payload_bytes", output)
            for role in ("produce", "consume"):
                descriptor = controller.read(controller.args.client, "after", role)
                argv = descriptor["argv"]
                phase_id = argv[argv.index("--run-id") + 1]
                self.assertLessEqual(len(phase_id), 64)
                self.assertNotEqual(self.case["run_id"], phase_id)
                self.assertEqual(self.case["run_id"], descriptor["run_id"])
                self.assertEqual(role == "produce", "--max-messages" in argv)
                self.assertEqual(role == "produce", "--duration-seconds" in argv)
        self.assertTrue(all(not call[2].get("renew") for call in self.boundary.calls if call[0] == "snapshot"))
        self.assertTrue(all(call[0] in ("check", "start", "snapshot", "stop") for call in self.boundary.calls))

    def test_consumer_barrier_and_partial_or_stale_writer_evidence_never_pass(self):
        controllers = self.prepare_phase("before")
        consumer_c = self.boundary.tasks[cli.task_id(self.case, "c", "before", "consume")]
        consumer_c["frame_age_ms"] = 16000
        with self.assertRaisesRegex(CaseError, "barrier"), patch.object(controllers[0], "attach", return_value=None):
            controllers[0].scoped("produce")
        consumer_c["frame_age_ms"] = 0
        for controller in controllers:
            with patch.object(controller, "attach", return_value=None):
                controller.scoped("produce")
        self.boundary.drive("before", 41)
        partial = self.boundary.tasks[cli.task_id(self.case, "c", "before", "produce")]
        partial["last_frame"]["unconfirmed_messages"] = 1
        frame = self.boundary.tasks[cli.task_id(self.case, "a", "before", "watch")]["last_frame"]["retained_window"]
        self.assertFalse(controllers[0].evidence(copy.deepcopy(frame))["drained"])
        partial["last_frame"]["unconfirmed_messages"] = 0
        consumer_c["frame_age_ms"] = 16000
        self.assertFalse(controllers[0].evidence(copy.deepcopy(frame))["drained"])
        unknown = copy.deepcopy(frame)
        unknown["window"]["unknown"]["tx_bytes"] = 1
        self.assertEqual("incomplete", observation(unknown, 0, unknown["workload"])[0])

    def test_attach_disconnected_and_unknown_show_recovery_and_never_success(self):
        controller = self.prepare_phase("before")[0]
        task = cli.task_id(self.case, "a", "before", "watch")
        for state in ("disconnected", "unknown"):
            self.boundary.break_task = task if state == "disconnected" else None
            self.boundary.tasks[task]["state"] = state
            output = io.StringIO()
            with self.assertRaisesRegex(CaseError, "Stop unconfirmed"), contextlib.redirect_stderr(output):
                controller.attach("watch")
            self.assertIn("controller", output.getvalue())
            self.assertIn(" status ", output.getvalue())
            self.assertIn(" stop ", output.getvalue())
            self.assertIn("--state-dir", output.getvalue())

    def test_scope_failure_is_nonzero_and_never_starts_watch(self):
        controller = self.controller("a")
        controller.check()
        self.boundary.fail_scope = True
        with self.assertRaisesRegex(CaseError, "Remote role failed"), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            controller.scoped("scope-prepare")
        self.assertNotIn(cli.task_id(self.case, "a", "before", "watch"), self.boundary.tasks)

    def test_start_ack_loss_keeps_controller_and_reports_exact_recovery_without_traceback(self):
        controller = self.controller("a")
        controller.check()
        self.boundary.lose_start_ack = True
        stderr = io.StringIO()
        arguments = ["runtime-prepare", "--config", str(self.config), "--client", "a", "--cohort", "a,b,c", "--state-dir", str(self.root / "generated/state")]
        with self.assertRaises(SystemExit) as exit_result, contextlib.redirect_stderr(stderr):
            cli.main(arguments, api=api)
        self.assertEqual(2, exit_result.exception.code)
        saved = controller.read("a", "before", "scope-prepare")
        self.assertEqual(saved["controller_id"], self.boundary.tasks[saved["task_id"]]["controller_id"])
        self.assertIn(saved["task_id"], stderr.getvalue())
        self.assertIn("start-unconfirmed", stderr.getvalue())
        self.assertIn("--role scope-prepare", stderr.getvalue())
        self.assertIn(" status ", stderr.getvalue())
        self.assertIn(" stop ", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        self.assertNotIn("--spec-json", stderr.getvalue())

    def test_metrics_reader_requires_matching_phase_and_new_success(self):
        controller = self.prepare_phase("before")[0]
        spec = self.boundary.specs[("a", "before")]
        now = [100.0]
        reader = WorkloadReader(spec, clock=lambda: now[0], wall=lambda: now[0])
        for sequence, messages in ((1, 0), (2, 10)):
            for role, task in spec["workload_task_ids"].items():
                path = pathlib.Path(spec["remote_root"]) / "state" / task / "metrics.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps({"schema_version": 1, "event": "progress", "state": "running", "role": role,
                                            "run_id": spec["workload_run_id"], "sample_seq": sequence, "messages": messages, "payload_bytes": messages * 1024}))
                os.utime(path, (now[0], now[0]))
            measured = reader.frame()
            now[0] += 1
        self.assertTrue(measured["produce_active"])
        self.assertTrue(measured["consume_active"])
        now[0] += 20
        self.assertFalse(reader.frame()["frames_fresh"])

    def test_scope_module_exit_code_preserves_unverified_result_and_cleanup_failure(self):
        from cross_az import scope
        for operation, result in (("prepare", {"state": "prepared", "source_proof": {"verified": False}}),
                                  ("cleanup", {"state": "cleanup_incomplete"})):
            fake = SimpleNamespace(prepare=lambda: result, cleanup=lambda: result)
            stdout = io.StringIO()
            with patch.object(scope, "Scope", return_value=fake), patch.object(sys, "argv", ["scope", operation, "--spec-json", "{}"]), contextlib.redirect_stdout(stdout), self.assertRaises(SystemExit) as failed:
                scope.main()
            self.assertEqual(2, failed.exception.code)
            self.assertEqual(result, json.loads(stdout.getvalue())["result"])
        fake = SimpleNamespace(prepare=lambda: {"state": "prepared", "source_proof": {"verified": True}})
        with patch.object(scope, "Scope", return_value=fake), patch.object(sys, "argv", ["scope", "prepare", "--spec-json", "{}"]), contextlib.redirect_stdout(io.StringIO()):
            self.assertIsNone(scope.main())

    def test_watch_age_includes_slow_related_queries_and_terminal_sample_is_historical(self):
        controllers = self.prepare_phase("before")
        for controller in controllers:
            with patch.object(controller, "attach", return_value=None):
                controller.scoped("produce")
        self.boundary.drive("before", 0)
        controller = controllers[0]
        task = cli.task_id(self.case, "a", "before", "watch")
        self.boundary.tasks[task]["last_frame"] = self.boundary.business_frame("a", "before", 0)
        now = [100.0]
        controller.clock = lambda: now[0]
        self.boundary.query_clock = now
        self.boundary.snapshot_delay = 10
        self.boundary.finish_watch_after_queries = task
        stdout = io.StringIO()
        with patch("time.sleep", return_value=None), contextlib.redirect_stdout(stdout):
            controller.attach("watch")
        output = stdout.getvalue()
        self.assertIn("State stale", output)
        self.assertRegex(output, r"Age 20\.0[0-9]s")
        self.assertIn("State stopped", output)
        self.assertIn("HISTORICAL final window", output)
        self.assertNotIn("No cross-AZ TCP traffic observed", output)
        self.assertIn("2026-11-10T10:00:00Z", output)

    def test_ready_and_drain_age_snapshots_at_final_decision_time(self):
        controllers = self.prepare_phase("before")
        now = [100.0]
        controller = controllers[0]
        controller.clock = lambda: now[0]
        sampled = controller.sample_roles(self.case["clients"], ("consume",))
        for sample in sampled.values():
            sample["_case_received_mono"] = 100
        now[0] = 120
        with patch.object(controller, "sample_roles", return_value=sampled), patch.object(controller, "attach", return_value=None), self.assertRaisesRegex(CaseError, "barrier"):
            controller.scoped("produce")
        for item in controllers:
            with patch.object(item, "attach", return_value=None):
                item.scoped("produce")
        self.boundary.drive("before", 41)
        samples = controller.sample_roles(self.case["clients"], ("produce", "consume"))
        for sample in samples.values():
            sample["_case_received_mono"] = 120
        now[0] = 140
        frame = self.boundary.business_frame("a", "before", 41)
        result = controller.evidence(frame, samples)
        self.assertFalse(result["drained"])
        self.assertIn("stale", result["offset_issue"])

    def test_related_public_transport_failure_stops_owned_watch_or_reports_recovery(self):
        controllers = self.prepare_phase("before")
        for controller in controllers:
            with patch.object(controller, "attach", return_value=None):
                controller.scoped("produce")
        self.boundary.drive("before", 41)
        controller = controllers[0]
        watch_task = cli.task_id(self.case, "a", "before", "watch")
        self.boundary.break_task = cli.task_id(self.case, "a", "before", "consume")
        stderr = io.StringIO()
        with self.assertRaisesRegex(CaseError, "stopped and confirmed"), contextlib.redirect_stderr(stderr):
            controller.attach("watch")
        self.assertTrue(self.boundary.tasks[watch_task]["stop_confirmed"])
        self.assertIn(watch_task, stderr.getvalue())
        # If the independent stop also fails, retain explicit ownership and
        # commands rather than exiting through the generic main diagnostic.
        self.boundary.tasks[watch_task].update(state="running", stop_confirmed=False)
        self.boundary.unconfirm_watch_stop = True
        stderr = io.StringIO()
        with self.assertRaisesRegex(CaseError, "Stop unconfirmed"), contextlib.redirect_stderr(stderr):
            controller.attach("watch")
        self.assertIn("controller", stderr.getvalue())
        self.assertIn(watch_task, stderr.getvalue())
        self.assertIn(" status ", stderr.getvalue())
        self.assertIn(" stop ", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
