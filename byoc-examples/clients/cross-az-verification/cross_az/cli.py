"""Local manual case controller. Every remote role requires an explicit call."""
import argparse
import concurrent.futures
import copy
import hashlib
import importlib
import json
import os
import pathlib
import shlex
import subprocess
import sys
import time
import uuid

from .config import CaseError, aws_candidates, fingerprint, load, prepare
from .view import Freshness, drained, ready_barrier, render, targets


def runner_api():
    path = pathlib.Path(__file__).resolve().parents[4] / "tools" / "kafka-workload"
    sys.path.insert(0, str(path))
    return importlib.import_module("runner")


def task_id(case, client, phase, role):
    key = case["run_id"] + ":" + client + ":" + phase + ":" + role
    return "az-" + hashlib.sha256(key.encode()).hexdigest()[:32] + "-" + role


def phase_run_id(case, phase):
    """Java accepts 64 characters; a full-length case ID remains valid."""
    return "az-" + fingerprint({"run_id": case["run_id"], "phase": phase})[:32] + "-" + phase


class Controller:
    def __init__(self, case, args, api):
        self.case, self.args, self.api = case, args, api
        self.clock = time.monotonic
        self.cohort = args.cohort.split(",") if args.cohort else list(case["clients"])
        if args.client not in self.cohort or any(c not in case["clients"] for c in self.cohort) or len(set(self.cohort)) != len(self.cohort):
            raise CaseError("Client must belong to the selected cohort")
        self.root = pathlib.Path(args.state_dir).resolve()
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.root.is_symlink() or self.root.stat().st_mode & 0o077:
            raise CaseError("Local state directory must have mode 0700")
        session_path = self.root / ("session-" + fingerprint(case["run_id"])[:16] + ".json")
        session = {"cohort": self.cohort, "case_fingerprint": fingerprint(case)}
        if session_path.exists():
            if json.loads(session_path.read_text()) != session:
                raise CaseError("Existing run uses a different case or cohort; choose a new run_id")
        else:
            self.write(session_path, session)

    def path(self, client, phase, suffix):
        return self.root / (task_id(self.case, client, phase, suffix) + ".json")

    def write(self, path, value):
        if path.exists():
            raise CaseError("Refusing to overwrite phase state; choose a new run_id")
        fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)

    def read(self, client, phase, role):
        try:
            return json.loads(self.path(client, phase, role).read_text())
        except FileNotFoundError:
            raise CaseError("Missing " + client + "/" + phase + "/" + role + "; run its explicit entry first") from None

    def runner(self, client):
        return self.case["clients"][client]["runner_file"]

    def snapshot(self, client, phase, role, renew=False):
        state = self.read(client, phase, role)
        snapshot = self.api.snapshot(self.runner(client), state["task_id"], controller_id=state["controller_id"] if renew else None, renew=renew)
        snapshot["_case_received_mono"] = self.clock()
        return snapshot

    def aged(self, snapshot):
        result = dict(snapshot)
        if result.get("frame_age_ms") is not None:
            result["frame_age_ms"] += max(0, self.clock() - result.get("_case_received_mono", self.clock())) * 1000
        return result

    def sample_roles(self, clients, roles, allow_missing=False):
        """Independent read-only requests overlap; each keeps its receipt time."""
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as workers:
            pending = {(client, role): workers.submit(self.snapshot, client, self.args.phase, role) for client in clients for role in roles}
            result = {}
            for key, future in pending.items():
                try:
                    result[key] = future.result()
                except CaseError:
                    if not allow_missing:
                        raise
                    result[key] = {"state": "not-started"}
        return result

    def check(self):
        client = self.case["clients"][self.args.client]
        requirements = {"remote_connection_file": client["remote_connection_file"],
                        "endpoints": [{"host": b["ip"], "port": b["port"]} for b in self.case["brokers"]],
                        "expected_zone_id": client["zone_id"], "tools": ["ip", "iptables"], "capture": True, "java": True,
                        "forbid_az_overrides": True}
        result = self.api.check(self.runner(self.args.client), requirements)
        result["case_source_verified"] = False
        result["case_issues"] = ["Source proof requires explicit runtime-prepare; host identity alone does not prove SNAT source", "Verify product routing capability, WAL/network conditions, original physical leaders and absence of client AZ overrides"]
        # Rechecking is read-only remotely and may refresh local evidence.
        path = self.path(self.args.client, self.args.phase, "check")
        if path.exists():
            path.unlink()
        self.write(path, result)
        return result

    def spec(self):
        client = self.case["clients"][self.args.client]
        runner = json.loads(pathlib.Path(client["runner_file"]).read_text())
        check = self.read(self.args.client, self.args.phase, "check")
        identity = check.get("identity", {})
        overrides = check.get("permissions", {}).get("az_overrides", {})
        return {"schema_version": 1, "run_id": self.case["run_id"], "client_id": self.args.client,
                "phase": self.args.phase, "scope_id": task_id(self.case, self.args.client, self.args.phase, "scope"),
                "scope_cidr": client["scope_cidr"], "source_ip": client["source_ip"], "zone_id": client["zone_id"],
                "actual_zone_id": identity.get("zone_id"), "identity_verified": bool(check.get("ok") and identity.get("identity_verified") and identity.get("private_ip") == client["source_ip"] and overrides.get("checked") and overrides.get("present") is False),
                "actual_hostname": identity.get("hostname"), "actual_instance_id": identity.get("instance_id"),
                "workload_run_id": phase_run_id(self.case, self.args.phase),
                "remote_root": runner["remote_root"], "brokers": self.case["brokers"],
                "workload_task_ids": {role: task_id(self.case, self.args.client, self.args.phase, role) for role in ("produce", "consume")},
                "window_seconds": self.case["observation"]["window_seconds"],
                "warmup_seconds": self.case["observation"]["warmup_seconds"]}

    def start(self, role, argv, scope_id=None):
        path = self.path(self.args.client, self.args.phase, role)
        if path.exists():
            raise CaseError("Phase role already exists; use status/stop or choose a new run_id")
        descriptor = {"schema_version": 1, "task_id": task_id(self.case, self.args.client, self.args.phase, role),
                      "controller_id": uuid.uuid4().hex, "role": role, "run_id": self.case["run_id"],
                      "phase": self.args.phase, "argv": argv}
        if scope_id:
            descriptor["scope_id"] = scope_id
        self.write(path, descriptor)
        try:
            return self.api.start(self.runner(self.args.client), descriptor)
        except Exception:
            # Persisted before submission: an absent acknowledgement cannot
            # tell us whether the remote task started. Never start a duplicate.
            self.recovery(role, {"state": "start-unconfirmed"})

    def notice(self, message):
        print(message, file=sys.stderr)

    def role_plan(self, role, verify_barrier=True):
        spec = self.spec()
        if role in ("scope-prepare", "scope-cleanup"):
            self.notice("Explicit remote OS operation: " + role + "; only owned namespace/veth/SNAT rules")
            operation = "prepare" if role == "scope-prepare" else "cleanup"
            return ["python3", "-m", "cross_az.scope", operation, "--spec-json", json.dumps(spec, separators=(",", ":"))], None
        scope_snapshot = self.snapshot(self.args.client, self.args.phase, "scope-prepare")
        ledger = (scope_snapshot.get("last_frame") or {}).get("result", {})
        if scope_snapshot.get("state") != "stopped" or not scope_snapshot.get("stop_confirmed") or scope_snapshot.get("exit_code") != 0 or ledger.get("state") != "prepared" or not ledger.get("source_proof", {}).get("verified"):
            raise CaseError("Prepared scope with verified ENI source proof required")
        if role == "watch":
            argv = ["python3", "-m", "cross_az.collector", "--spec-json", json.dumps(spec, separators=(",", ":"))]
        else:
            if role == "produce" and verify_barrier:
                sampled = self.sample_roles(self.cohort, ("consume",))
                snapshots = {c: self.aged(sampled[(c, "consume")]) for c in self.cohort}
                missing = ready_barrier(snapshots, self.case["workload"]["partitions"], self.case["topic"], phase_run_id(self.case, self.args.phase))
                if missing:
                    raise CaseError("Consumer current-end barrier missing: " + ",".join(missing))
            client = self.case["clients"][self.args.client]
            workload = self.case["workload"]
            argv = ["ip", "netns", "exec", ledger["namespace"], "./workload", role,
                    "--config", client["remote_connection_file"], "--topic", self.case["topic"],
                    "--run-id", phase_run_id(self.case, self.args.phase)]
            if role == "consume":
                argv += ["--group", task_id(self.case, self.args.client, self.args.phase, "group"), "--start-position", "current-end"]
            else:
                argv += ["--rate-mibps", str(workload["rate_mibps"]), "--record-bytes", str(workload["record_bytes"]),
                         "--compression", workload["compression"], "--partition-mode", "round-robin"]
            for key in (("duration_seconds", "max_messages", "max_errors") if role == "produce" else ("max_errors",)):
                if key in workload:
                    argv += ["--" + key.replace("_", "-"), str(workload[key])]
        return argv, spec["scope_id"]

    def scoped(self, role):
        argv, scope_id = self.role_plan(role)
        self.start(role, argv, scope_id)
        return self.attach(role)

    def evidence(self, frame, sampled=None):
        finals, consumers = [], []
        issues = []
        sampled = sampled if sampled is not None else self.sample_roles(self.cohort, ("produce", "consume"))
        for client in self.cohort:
            producer = self.aged(sampled[(client, "produce")])
            consumer = self.aged(sampled[(client, "consume")])
            produced, consumed = producer.get("last_frame") or {}, consumer.get("last_frame") or {}
            expected = phase_run_id(self.case, self.args.phase)
            if producer.get("state") not in ("stopped", "failed") or not producer.get("stop_confirmed") or producer.get("application_exit_code") != 0:
                issues.append(client + " producer has no confirmed successful final")
            if produced.get("run_id") != expected or produced.get("role") != "produce":
                issues.append(client + " producer phase identity differs")
            if consumed.get("run_id") != expected or consumed.get("role") != "consume" or consumed.get("errors", 0):
                issues.append(client + " consumer phase identity/errors incomplete")
            terminal = consumer.get("state") in ("stopped", "failed") and consumer.get("stop_confirmed") and consumed.get("event") == "final" and consumed.get("exit_code") == 0
            fresh_running = consumer.get("state") in ("ready", "running") and consumer.get("frame_age_ms") is not None and consumer["frame_age_ms"] <= 15000
            if not terminal and not fresh_running:
                issues.append(client + " consumer progress stale or unconfirmed")
            finals.append(produced)
            consumers.append(consumed)
        target, error = targets(finals)
        if issues:
            error = "; ".join(issues)
        frame.update(topology_fingerprint=fingerprint({"clients": self.case["clients"], "brokers": self.case["brokers"]}),
                     workload_fingerprint=fingerprint(self.case["workload"]), cohort=self.cohort,
                     target_next_offsets=target, offset_issue=error,
                     drained=not error and all(drained(c.get("next_offsets", {}), target) for c in consumers),
                     successful_messages=sum(p.get("messages", 0) for p in finals),
                     successful_payload_bytes=sum(p.get("payload_bytes", 0) for p in finals),
                     partition_coverage=sorted(target))
        return frame

    def recovery(self, role, snapshot):
        state = self.read(self.args.client, self.args.phase, role)
        entry = str(pathlib.Path(__file__).resolve().parent.parent / "az-case")
        options = ["--config", str(pathlib.Path(self.args.config).resolve()), "--state-dir", str(self.root),
                   "--client", self.args.client, "--phase", self.args.phase, "--role", role, "--cohort", ",".join(self.cohort)]
        print("State {} | Stop unconfirmed | task {} | controller {}".format(snapshot.get("state", "unknown"), state["task_id"], state["controller_id"]), file=sys.stderr)
        for operation in ("status", "stop"):
            print(shlex.join([entry, operation] + options), file=sys.stderr)
        raise CaseError("Stop unconfirmed; retain state and use the displayed status/stop commands")

    def stop_after_query_failure(self, role):
        state = self.read(self.args.client, self.args.phase, role)
        try:
            result = self.api.stop(self.runner(self.args.client), state["task_id"], state["controller_id"])
        except Exception:
            result = {"state": "disconnected", "stop_confirmed": False}
        if not result.get("stop_confirmed"):
            self.recovery(role, result)
        print("Related status unavailable | {} stop confirmed | task {} | controller {}".format(role, state["task_id"], state["controller_id"]), file=sys.stderr)
        raise CaseError("Related status unavailable; the owned " + role + " task was stopped and confirmed")

    def attach(self, role):
        state = self.read(self.args.client, self.args.phase, role)
        freshness = Freshness(clock=self.clock)
        baseline_path = self.path(self.args.client, "before", "baseline")
        baseline = json.loads(baseline_path.read_text()) if baseline_path.exists() else None
        snapshot = {"state": "unknown", "stop_confirmed": False}
        try:
            for snapshot in self.api.attach(self.runner(self.args.client), state["task_id"], state["controller_id"]):
                if snapshot.get("state") in ("disconnected", "unknown"):
                    self.recovery(role, snapshot)
                if role != "watch" or self.args.json:
                    print(json.dumps(snapshot), flush=True)
                    continue
                frame = snapshot.get("last_frame")
                if not frame:
                    print("Waiting for remote capture frame; no zero-byte conclusion", flush=True)
                    continue
                # runner.frame_age_ms already includes its measured RTT.
                received = self.clock()
                received_age = freshness.age(snapshot)
                frame["identity"] = snapshot.get("identity") or {}
                frame["task_id"] = state["task_id"]
                frame["role_states"] = {"watch": snapshot.get("state")}
                try:
                    sampled = self.sample_roles(self.cohort if baseline else (self.args.client,), ("produce", "consume"), allow_missing=True)
                    for related in ("produce", "consume"):
                        frame["role_states"][related] = sampled[(self.args.client, related)].get("state", "unknown")
                except Exception:
                    self.stop_after_query_failure(role)
                workload = dict(frame.get("workload", {}))
                workload["frames_fresh"] = workload.get("frames_fresh", False) and all(
                    self.aged(sampled[(self.args.client, related)]).get("frame_age_ms") is not None
                    and self.aged(sampled[(self.args.client, related)])["frame_age_ms"] <= 15000
                    and sampled[(self.args.client, related)].get("state") in ("ready", "running")
                    for related in ("produce", "consume"))
                if baseline:
                    try:
                        retained = frame.get("retained_window")
                        if retained:
                            self.evidence(retained, sampled)
                    except CaseError:
                        pass
                age = received_age + max(0, self.clock() - received)
                print(render(frame, age, workload, self.case["observation"]["warmup_seconds"], baseline), flush=True)
            if not snapshot.get("stop_confirmed"):
                self.recovery(role, snapshot)
            expected_signal = snapshot.get("exit_code") in (130, 143) and snapshot.get("application_exit_code") == 0
            if snapshot.get("state") == "failed" or (snapshot.get("exit_code") not in (0, None) and not expected_signal):
                raise CaseError("Remote role failed; inspect status before retrying with a new run_id")
            if role == "scope-prepare" and not ((snapshot.get("last_frame") or {}).get("result", {}).get("source_proof", {}).get("verified")):
                raise CaseError("Source proof unverified; no workload was started")
        except KeyboardInterrupt:
            result = self.api.stop(self.runner(self.args.client), state["task_id"], state["controller_id"])
            print(json.dumps(result), flush=True)
            if not result.get("stop_confirmed"):
                self.recovery(role, result)


def main(argv=None, api=None):
    parser = argparse.ArgumentParser(description="Manual cross-AZ verification; no implicit cloud or cluster mutation")
    parser.add_argument("operation", choices=("prepare", "check", "discover-aws", "runtime-prepare", "runtime-cleanup", "watch", "produce", "consume", "snapshot", "status", "stop"))
    parser.add_argument("--config", required=True)
    parser.add_argument("--out")
    parser.add_argument("--clients")
    parser.add_argument("--cohort")
    parser.add_argument("--client")
    parser.add_argument("--phase", choices=("before", "after"), default="before")
    parser.add_argument("--role", choices=("watch", "produce", "consume", "scope-prepare", "scope-cleanup"), default="watch")
    parser.add_argument("--state-dir", default="generated/state")
    parser.add_argument("--name", default="baseline", choices=("baseline",))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--profile")
    parser.add_argument("--region")
    args = parser.parse_args(argv)
    try:
        case = load(args.config)
        if args.operation == "prepare":
            if not args.out:
                raise CaseError("prepare requires --out")
            result = prepare(case, args.config, args.out, args.clients.split(",") if args.clients else None)
        elif args.operation == "discover-aws":
            if not args.profile or not args.region:
                raise CaseError("Read-only discovery requires --profile and --region")
            result = aws_candidates(args.profile, args.region, lambda command: subprocess.check_output(command, text=True))
        else:
            if not args.client or args.client not in case["clients"]:
                raise CaseError("An existing --client is required")
            controller = Controller(case, args, api or runner_api())
            if args.operation == "check":
                result = controller.check()
            elif args.operation in ("runtime-prepare", "runtime-cleanup", "watch", "produce", "consume"):
                role = {"runtime-prepare": "scope-prepare", "runtime-cleanup": "scope-cleanup"}.get(args.operation, args.operation)
                controller.scoped(role)
                return
            elif args.operation == "status":
                try:
                    result = controller.snapshot(args.client, args.phase, args.role)
                except CaseError:
                    raise
                except Exception:
                    controller.recovery(args.role, {"state": "disconnected"})
            elif args.operation == "stop":
                state = controller.read(args.client, args.phase, args.role)
                result = controller.api.stop(controller.runner(args.client), state["task_id"], state["controller_id"])
                if not result.get("stop_confirmed"):
                    controller.recovery(args.role, result)
            else:
                if args.phase != "before":
                    raise CaseError("Baseline snapshot must come from before phase")
                snap = controller.snapshot(args.client, args.phase, "watch")
                if Freshness().age(snap) > 15:
                    raise CaseError("Cannot preserve stale baseline")
                retained = snap.get("last_frame", {}).get("retained_window")
                if not retained:
                    raise CaseError("No valid running business window was retained; do not snapshot an idle final window")
                result = controller.evidence(copy.deepcopy(retained))
                if not result.get("drained"):
                    raise CaseError("Cohort final offsets are incomplete or not drained; keep consumers running and retry snapshot")
                controller.write(controller.path(args.client, args.phase, "baseline"), result)
        print(json.dumps(result, indent=2), flush=True)
        if args.operation == "check" and not result.get("ok"):
            raise SystemExit(2)
    except Exception as error:
        print("az-case: " + (str(error) if isinstance(error, CaseError) else "Operation failed; inspect dependencies and safe input paths"), file=sys.stderr)
        raise SystemExit(2)
