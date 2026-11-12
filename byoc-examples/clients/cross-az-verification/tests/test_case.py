import contextlib
import copy
import io
import json
import pathlib
import socket
import struct
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from cross_az import cli
from cross_az.collector import CaptureDiagnostics, RetainedWindow, Window, WorkloadReader, parse_packet, receive, verify_source
from cross_az.config import CaseError, aws_candidates, load, longest_prefix, prepare, validate
from cross_az.scope import Scope, canonical_rule
from cross_az.view import Freshness, compare, drained, observation, ready_barrier, render, targets


HERE = pathlib.Path(__file__).resolve().parent.parent


def example():
    return json.loads((HERE / "examples/case.json").read_text())


def packet(src="198.18.240.2", dst="10.40.11.10", sport=40000, dport=9092, seq=123, size=1040, syn=False):
    ethernet = b"\x00" * 12 + b"\x08\x00"
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, size, 1, 0, 64, 6, 0, socket.inet_aton(src), socket.inet_aton(dst))
    tcp = struct.pack("!HHIIBBHHH", sport, dport, seq, 0, 0x50, 2 if syn else 0x10, 1000, 0, 0)
    return ethernet + ip + tcp


def ipv6_packet(next_header, payload):
    ethernet = b"\x00" * 12 + b"\x86\xdd"
    source = socket.inet_pton(socket.AF_INET6, "fe80::1")
    target = socket.inet_pton(socket.AF_INET6, "ff02::1")
    return ethernet + struct.pack("!IHBB16s16s", 6 << 28, len(payload), next_header, 255, source, target) + payload


class ConfigTests(unittest.TestCase):
    def test_longest_prefix_and_conflicting_equal_prefix(self):
        self.assertEqual("b", longest_prefix("10.1.2.4", {"10.0.0.0/8": "a", "10.1.0.0/16": "b"}))
        case = example()
        case["clients"]["client-b"] = dict(case["clients"]["client-a"], zone_id="example-az2")
        with self.assertRaisesRegex(CaseError, "Conflicting"):
            validate(case)

    def test_reject_bad_networks_and_overrides(self):
        for update in ({"source_cidrs": ["10.40.1.1/24"]}, {"source_ip": "::1"}, {"source_ip": "10.50.1.10"},
                       {"scope_cidr": "198.18.240.0/25"}, {"remote_connection_file": "relative"}, {"client_rack": "x"}):
            case = example()
            case["clients"]["client-a"].update(update)
            with self.subTest(update=update), self.assertRaises((CaseError, ValueError)):
                validate(case)
        case = example()
        case["workload"]["rate_mibps"] = float("nan")
        with self.assertRaises(CaseError):
            validate(case)

    def test_prepare_is_local_generates_cohort_and_independent_groups(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp)
            config = path / "case.json"
            config.write_text(json.dumps(example()))
            case = load(config)
            report = prepare(case, config, path / "generated", ["client-a"])
            self.assertIn("source_unverified", report["warnings"][0])
            self.assertEqual("example-az1@10.40.1.0/24\n", (path / "generated/zone-cidr.txt").read_text())
            before = (path / "generated/client-a/before/consume.sh").read_text()
            after = (path / "generated/client-a/after/consume.sh").read_text()
            self.assertIn("--phase before", before)
            self.assertIn("--phase after", after)
            self.assertIn("--cohort client-a", before)
            self.assertEqual(0o700, (path / "generated/client-a/before/consume.sh").stat().st_mode & 0o777)
            self.assertEqual(0o700, (path / "generated/topic-create.sh").stat().st_mode & 0o777)
            self.assertNotIn("REMOTE_PROPERTIES", (path / "generated/topic-command.txt").read_text())
            self.assertNotEqual(cli.task_id(case, "client-a", "before", "group"), cli.task_id(case, "client-a", "after", "group"))
            self.assertFalse((path / "generated/state").exists())
            with self.assertRaises(CaseError):
                prepare(case, config, path / "generated")

    def test_aws_discovery_is_only_describe_and_unverified(self):
        seen = []
        result = aws_candidates("demo", "region", lambda argv: seen.append(argv) or '{"NetworkInterfaces": []}')
        self.assertFalse(result["verified"])
        self.assertIn("describe-network-interfaces", seen[0])
        self.assertNotIn("create", " ".join(seen[0]))


class PacketTests(unittest.TestCase):
    def test_ipv6_nd_rs_and_mld_are_confirmed_non_tcp(self):
        # Real wire shapes seen during the EC2 namespace's initial DAD:
        # NS=86 bytes, RS=70 bytes, MLD+hop-by-hop=90 bytes.
        ns = ipv6_packet(58, struct.pack("!BBHI16s", 135, 0, 0, 0, socket.inet_pton(socket.AF_INET6, "fe80::1")) + b"\0" * 8)
        rs = ipv6_packet(58, struct.pack("!BBHI", 133, 0, 0, 0) + b"\0" * 8)
        mld = ipv6_packet(0, bytes([58, 0, 5, 2, 0, 0, 1, 0]) + bytes([143, 0, 0, 0]) + b"\0" * 24)
        self.assertEqual([86, 70, 90], [len(ns), len(rs), len(mld)])
        for fixture in (ns, rs, mld):
            with self.subTest(length=len(fixture)):
                self.assertIsNone(parse_packet(fixture, 4))

    def test_ipv6_tcp_unknown_truncation_fragment_and_extension_budget_still_fail(self):
        samples = [ipv6_packet(6, b"\0" * 20), ipv6_packet(250, b"\0" * 8),
                   ipv6_packet(44, b"\0" * 16), ipv6_packet(0, bytes([58, 8]) + b"\0" * 6),
                   ipv6_packet(58, b"\0" * 4)]
        # Nine extension headers exceed the fixed eight-header walk budget.
        samples.append(ipv6_packet(0, (bytes([0, 0]) + b"\0" * 6) * 8 + bytes([58, 0]) + b"\0" * 6 + b"\0" * 8))
        for fixture in samples:
            with self.subTest(length=len(fixture)), self.assertRaises(ValueError):
                parse_packet(fixture, 4)
        # A long unsupported extension stream cannot create unbounded storage.
        diagnostics = CaptureDiagnostics()
        for _ in range(10000):
            try:
                parse_packet(samples[-1], 4)
            except ValueError as error:
                diagnostics.error(error)
        quality = diagnostics.frame()
        self.assertEqual({"ipv6_header_budget": 10000}, quality["error_codes"])
        self.assertFalse(quality["complete"])

    def test_capture_diagnostics_are_safe_finite_codes_and_drop_counters(self):
        diagnostics = CaptureDiagnostics()
        diagnostics.error(ValueError("Truncated IPv6 extension header"))
        diagnostics.error(ValueError("Kernel packet timestamp unavailable"))
        diagnostics.error(ValueError("sensitive raw error must never be retained"))
        diagnostics.kernel_packets, diagnostics.kernel_drops, diagnostics.overflows = 50, 2, 1
        frame = diagnostics.frame()
        self.assertFalse(frame["complete"])
        self.assertEqual(3, frame["parse_errors"])
        self.assertEqual(2, frame["kernel_drops"])
        self.assertEqual(1, frame["syn_overflows"])
        self.assertNotIn("sensitive", json.dumps(frame))
    def test_headers_l3_length_and_direction_without_payload(self):
        tx = parse_packet(packet(), 4, 1)
        self.assertEqual(1040, tx["bytes"])
        self.assertEqual("tx", tx["direction"])
        self.assertEqual("rx", parse_packet(packet(), 0)["direction"])
        self.assertIsNone(parse_packet(packet(), 3))
        self.assertNotIn("payload", tx)

    def test_unsupported_and_truncated_paths_are_errors(self):
        for data in (b"short", b"\x00" * 12 + b"\x86\xdd", packet()[:-1]):
            with self.assertRaises(ValueError):
                parse_packet(data, 4)
        fragmented = bytearray(packet())
        fragmented[20:22] = b"\x20\x00"
        with self.assertRaises(ValueError):
            parse_packet(fragmented, 4)

    def test_unknown_peers_counted_and_windows_independent(self):
        now = [100.0]
        window = Window(example()["brokers"], "example-az1", seconds=10, clock=lambda: now[0])
        window.add(parse_packet(packet(), 4))
        window.add(parse_packet(packet(dst="10.40.12.10", size=41), 4))
        window.add(parse_packet(packet(dst="10.99.1.8", size=42), 4))
        frame = window.frame(True, True)
        self.assertEqual(1040, frame["window"]["same"]["tx_bytes"])
        self.assertEqual(41, frame["window"]["cross"]["tx_bytes"])
        self.assertEqual(42, frame["window"]["unknown"]["tx_bytes"])
        window.loss("kernel_drops", 1)
        self.assertFalse(window.frame(True, True)["quality"]["complete"])
        now[0] += 11
        later = window.frame(True, True)
        self.assertEqual(0, later["window"]["cross"]["tx_bytes"])
        self.assertEqual(41, later["totals"]["cross"]["tx_bytes"])
        after = Window(example()["brokers"], "example-az1", clock=lambda: now[0])
        self.assertEqual(0, after.frame()["totals"]["cross"]["tx_bytes"])

    def test_source_proof_nat_port_and_wrong_or_ambiguous_source(self):
        ns = parse_packet(packet(syn=True), 4, 1, "kernel")
        host = parse_packet(packet(src="10.40.1.10", sport=50000, syn=True), 4, 1.01, "kernel")
        self.assertTrue(verify_source([ns], [host], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([ns], [host], "10.40.1.11", ("10.40.11.10", 9092))["verified"])
        duplicate = dict(host, sport=50001)
        self.assertFalse(verify_source([ns], [host, duplicate], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([ns], [dict(host, seq=999)], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([ns], [dict(host, time=4)], "10.40.1.10", ("10.40.11.10", 9092))["verified"])

    def test_fractional_boundary_never_expires_live_cross_packet_early(self):
        now = [100.9]
        window = Window(example()["brokers"], "example-az1", clock=lambda: now[0])
        window.add(parse_packet(packet(dst="10.40.12.10", size=41), 4))
        now[0] = 110.1
        self.assertEqual(41, window.frame(True, True)["window"]["cross"]["tx_bytes"])
        now[0] = 110.9
        self.assertEqual(41, window.frame(True, True)["window"]["cross"]["tx_bytes"])
        now[0] = 110.9001
        self.assertEqual(0, window.frame(True, True)["window"]["cross"]["tx_bytes"])

    def test_source_kernel_time_survives_reversed_read_order_retransmits_and_rejects_ambiguity(self):
        ns = parse_packet(packet(syn=True), 4, 100, "kernel")
        host = parse_packet(packet(src="10.40.1.10", sport=50000, syn=True), 4, 100.001, "kernel")
        # The namespace process reads late; kernel timestamps still establish
        # ordering on the common host clock, independently of scheduling.
        ns["read_time"], host["read_time"] = 105, 101
        retransmit_ns, retransmit_host = dict(ns, time=101), dict(host, time=101.001)
        self.assertTrue(verify_source([ns, retransmit_ns], [retransmit_host, host], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([ns], [dict(host, time=99.999)], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([dict(ns, timestamp_source="userspace")], [host], "10.40.1.10", ("10.40.11.10", 9092))["verified"])
        self.assertFalse(verify_source([ns, dict(ns, sport=40001)], [host], "10.40.1.10", ("10.40.11.10", 9092))["verified"])

    def test_receive_uses_kernel_ancillary_timestamp_not_read_time(self):
        class FakeSocket:
            def recvmsg(self, data_size, ancillary_size):
                return packet(syn=True), [(socket.SOL_SOCKET, 35, struct.pack("ll", 100, 900000000))], 0, ("eth0", 0, 4)
        self.assertEqual(100.9, receive(FakeSocket())["time"])
        self.assertEqual("kernel", receive(FakeSocket())["timestamp_source"])


class ViewTests(unittest.TestCase):
    def frame(self):
        window = Window(example()["brokers"], "example-az1")
        window.add(parse_packet(packet(), 4))
        result = window.frame(True, True)
        result["elapsed_seconds"] = 100
        return result

    def business_frame(self):
        value = self.frame()
        value.update(sample_time="2026-11-10T10:00:00Z", warmup_seconds=10, capture_frame_age_ms=0,
                     topology_fingerprint="t", workload_fingerprint="w", cohort=["a"], drained=True,
                     successful_messages=600, successful_payload_bytes=614400, partition_coverage=["t:0"])
        value["workload"] = {"produce_active": True, "consume_active": True, "frames_fresh": True,
                             "produce_running": True, "consume_running": True,
                             "window_success": {role: {"messages": 90, "payload_bytes": 92160, "covered_seconds": 9} for role in ("produce", "consume")}}
        return value

    def test_zero_requires_success_freshness_quality_and_exact_raw_zero(self):
        frame = self.frame()
        active = {"produce_active": True, "consume_active": True, "frames_fresh": True}
        self.assertIn("No cross-AZ", observation(frame, 0, active)[1])
        self.assertEqual("waiting", observation(frame, 0, {})[0])
        self.assertEqual("stale", observation(frame, 16, active)[0])
        for key in ("source_verified", "scope_intact", "complete"):
            bad = copy.deepcopy(frame)
            bad["quality"][key] = False
            self.assertEqual("incomplete", observation(bad, 0, active)[0])
        frame["window"]["cross"]["tx_bytes"] = 1
        self.assertIn("Cross-AZ bytes observed", observation(frame, 0, active)[1])
        self.assertIn("cross window TX 1 B", render(frame, 0, active))
        frame["window"]["unknown"]["rx_bytes"] = 1
        self.assertEqual("incomplete", observation(frame, 0, active)[0])

    def test_repeated_frame_does_not_refresh_age(self):
        now = [100]
        freshness = Freshness(clock=lambda: now[0])
        snap = {"task_id": "x", "frame_seq": 1, "frame_age_ms": 0}
        self.assertEqual(0, freshness.age(snap))
        now[0] += 20
        self.assertEqual(20, freshness.age(snap))
        snap["frame_seq"] = 2
        self.assertEqual(0, freshness.age(snap))

    def test_inclusive_merge_and_exclusive_drain(self):
        finals = [{"event": "final", "max_acked_offsets": {"t:0": 109}}, {"event": "final", "max_acked_offsets": {"t:0": 108, "t:1": 50}}]
        target, error = targets(finals)
        self.assertIsNone(error)
        self.assertEqual({"t:0": 110, "t:1": 51}, target)
        self.assertFalse(drained({"t:0": 109, "t:1": 51}, target))
        self.assertTrue(drained({"t:0": 110, "t:1": 51}, target))
        self.assertFalse(drained({}, {}))
        self.assertIsNotNone(targets([dict(finals[0], unconfirmed_messages=1)])[1])

    def test_all_selected_consumers_must_be_ready_and_fresh(self):
        good = {"state": "running", "frame_age_ms": 0, "ready_frame": {"event": "ready", "start_offsets": {"t:0": 10}}}
        snapshots = {"a": good, "b": dict(good, frame_age_ms=16000)}
        self.assertEqual(["b"], ready_barrier(snapshots, 1, "t"))
        self.assertEqual([], ready_barrier({"a": good}, 1, "t"))

    def test_baseline_without_cross_or_drain_is_not_improvement(self):
        baseline = self.frame()
        result = compare(baseline, copy.deepcopy(baseline))
        self.assertFalse(result["comparable"])
        self.assertIn("Baseline has no cross-AZ distinction", result["reasons"])
        self.assertIn("before offset boundary incomplete", result["reasons"])

    def test_comparison_requires_the_window_itself_to_be_fresh_warm_and_equally_loaded(self):
        before = self.business_frame()
        before["window"]["cross"]["tx_bytes"] = 41
        after = self.business_frame()
        self.assertTrue(compare(before, after)["comparable"])
        after["workload"].update(produce_active=False, consume_active=False, frames_fresh=False)
        self.assertFalse(compare(before, after)["comparable"])
        after = self.business_frame()
        after["elapsed_seconds"] = 1
        self.assertFalse(compare(before, after)["comparable"])
        after = self.business_frame()
        after["workload"]["window_success"]["produce"]["messages"] = 89
        self.assertFalse(compare(before, after)["comparable"])

    def test_retained_business_window_survives_idle_final_frame(self):
        retained = RetainedWindow(10)
        valid = self.business_frame()
        valid["window"]["cross"]["tx_bytes"] = 41
        saved = retained.update(valid)
        idle = self.business_frame()
        idle.update(sample_time="2026-11-10T10:01:00Z", sample_seq=99)
        idle["workload"].update(produce_active=False, produce_running=False)
        current = retained.update(idle)
        self.assertEqual(saved["sample_time"], current["sample_time"])
        self.assertEqual(41, current["window"]["cross"]["tx_bytes"])
        idle["retained_window"] = current
        text = render(idle, 0, idle["workload"], baseline=saved)
        self.assertIn("HISTORICAL after sample 2026-11-10T10:00:00Z", text)
        self.assertIn("LIVE window", text)
        self.assertIn("B/s", text)


class ScopeTests(unittest.TestCase):
    def spec(self):
        return {"scope_id": "run-a-before", "scope_cidr": "198.18.240.0/24", "remote_root": "/opt/demo"}

    def test_allocator_does_not_take_another_scope_or_host_route(self):
        with tempfile.TemporaryDirectory() as temp:
            scope = Scope(self.spec(), root=temp)
            scope.root.mkdir(parents=True)
            first = scope._allocate([])
            (scope.root / "other.json").write_text(json.dumps({"subnet": str(first)}))
            second = scope._allocate([])
            self.assertNotEqual(first, second)
            with self.assertRaises(CaseError):
                scope._allocate([{"dst": "198.18.240.0/24"}])

    def test_dad_waits_for_stability_and_rejects_failure_or_timeout(self):
        def addresses(**flags):
            return json.dumps([{"ifname": "eth0", "addr_info": [{"family": "inet6", "local": "fe80::1", **flags}]}])
        now = [0.0]
        samples = iter([addresses(tentative=True), addresses(tentative=True), addresses()])
        scope = Scope(self.spec(), run=lambda argv: next(samples))
        scope.wait_for_dad(clock=lambda: now[0], sleep=lambda delay: now.__setitem__(0, now[0] + delay))
        self.assertEqual(0.2, now[0])
        scope.run = lambda argv: addresses(dadfailed=True)
        with self.assertRaisesRegex(CaseError, "failed"):
            scope.wait_for_dad(clock=lambda: now[0], sleep=lambda delay: None)
        scope.run = lambda argv: addresses(tentative=True)
        with self.assertRaisesRegex(CaseError, "timed out"):
            scope.wait_for_dad(timeout=0.3, clock=lambda: now[0], sleep=lambda delay: now.__setitem__(0, now[0] + delay))
        self.assertLessEqual(now[0], 0.5)

    def test_cleanup_refuses_drift_and_live_process_without_delete(self):
        with tempfile.TemporaryDirectory() as temp:
            calls = []
            scope = Scope(self.spec(), root=temp, run=lambda argv: calls.append(argv) or "123\n")
            scope.lock = lambda: contextlib.nullcontext()
            scope.read = lambda: {"owner": scope.spec["scope_id"]}
            scope.intact = lambda ledger, **kwargs: False
            with self.assertRaisesRegex(CaseError, "drift"):
                scope.cleanup()
            self.assertEqual([], calls)
            scope.intact = lambda ledger, **kwargs: True
            with self.assertRaisesRegex(CaseError, "active"):
                scope.cleanup()
            self.assertEqual([["ip", "netns", "pids", scope.ns]], calls)

    def test_disjoint_owned_scope_can_coexist_but_relevant_path_change_invalidates(self):
        with tempfile.TemporaryDirectory() as temp:
            tables = {"nat": ":POSTROUTING ACCEPT [0:0]\n:UNRELATED - [0:0]\n-A UNRELATED -j DROP\n", "filter": ":FORWARD ACCEPT [0:0]\n"}
            scope = Scope(self.spec(), root=temp, run=lambda argv: tables[argv[-1]])
            scope.root.mkdir(parents=True)
            ledger = {"subnet": "198.18.240.0/30"}
            before = scope.rules_snapshot(ledger)
            other_id = "run-a-after"
            token = __import__("hashlib").sha256(other_id.encode()).hexdigest()[:10]
            command = ["iptables", "-w", "5", "-t", "nat", "-A", "POSTROUTING", "-s", "198.18.240.4/30", "-o", "ens5", "-m", "comment", "--comment", "automq-az:" + token, "-j", "AZN" + token]
            other = {"owner": other_id, "namespace": "az-" + token, "veth": "azh" + token, "subnet": "198.18.240.4/30", "rules": [command]}
            (scope.root / (other_id + ".json")).write_text(json.dumps(other))
            import shlex
            tables["nat"] += ":AZN" + token + " - [0:0]\n" + shlex.join(command[5:]) + "\n"
            self.assertEqual(before, scope.rules_snapshot(ledger))
            # Unreachable host chain changes have no bearing on this source.
            tables["nat"] += "-A UNRELATED -j ACCEPT\n"
            self.assertEqual(before, scope.rules_snapshot(ledger))
            # A broad SNAT preceding our jump can affect this scope, so it must
            # remain in the effective path fingerprint and invalidate proof.
            tables["nat"] += "-A POSTROUTING -o ens5 -j MASQUERADE\n"
            self.assertNotEqual(before, scope.rules_snapshot(ledger))

    def test_canonical_forward_both_directions_and_nat_match_exact_other_ledger(self):
        with tempfile.TemporaryDirectory() as temp:
            tables = {"nat": ":POSTROUTING ACCEPT [0:0]\n", "filter": ":FORWARD ACCEPT [0:0]\n"}
            scope = Scope(self.spec(), root=temp, run=lambda argv: tables[argv[-1]])
            scope.root.mkdir(parents=True)
            ledger = {"subnet": "198.18.240.0/30"}
            baseline = scope.rules_snapshot(ledger)
            other_id = "run-a-after"
            token = __import__("hashlib").sha256(other_id.encode()).hexdigest()[:10]
            veth, comment = "azh" + token, "automq-az:" + token
            rules = [
                ["iptables", "-w", "5", "-t", "filter", "-A", "FORWARD", "-i", veth, "-s", "198.18.240.4/30", "-m", "comment", "--comment", comment, "-j", "AZF" + token],
                ["iptables", "-w", "5", "-t", "filter", "-A", "FORWARD", "-o", veth, "-d", "198.18.240.4/30", "-m", "comment", "--comment", comment, "-j", "AZF" + token],
                ["iptables", "-w", "5", "-t", "nat", "-A", "POSTROUTING", "-s", "198.18.240.4/30", "-o", "ens5", "-m", "comment", "--comment", comment, "-j", "AZN" + token]]
            other = {"owner": other_id, "namespace": "az-" + token, "veth": veth, "subnet": "198.18.240.4/30", "rules": rules}
            (scope.root / (other_id + ".json")).write_text(json.dumps(other))
            # Real iptables-save ordering: addresses precede interfaces.
            forward_out = '-A FORWARD -s 198.18.240.4/30 -i {} -m comment --comment "{}" -j AZF{}\n'.format(veth, comment, token)
            forward_in = '-A FORWARD -d 198.18.240.4/30 -o {} -m comment --comment "{}" -j AZF{}\n'.format(veth, comment, token)
            nat = '-A POSTROUTING -s 198.18.240.4/30 -o ens5 -m comment --comment "{}" -j AZN{}\n'.format(comment, token)
            tables["filter"] += ":AZF" + token + " - [0:0]\n" + forward_out + forward_in
            tables["nat"] += ":AZN" + token + " - [0:0]\n" + nat
            self.assertEqual(baseline, scope.rules_snapshot(ledger))
            original_filter, original_nat = tables["filter"], tables["nat"]
            for original, altered in ((forward_out, forward_out.replace("198.18.240.4/30", "198.18.240.0/24")),
                                      (forward_out, forward_out.replace("-i " + veth, "-i ens5")),
                                      (forward_in, forward_in.replace("-d 198.18.240.4/30", "! -d 198.18.240.4/30")),
                                      (forward_in, forward_in.replace("-j AZF", "-j OTHER"))):
                with self.subTest(altered=altered):
                    tables["filter"] = original_filter.replace(original, altered)
                    self.assertNotEqual(baseline, scope.rules_snapshot(ledger))
            tables["filter"] = original_filter
            # Do not swallow duplicate rules beyond the number in the ledger.
            tables["filter"] += forward_out
            self.assertNotEqual(baseline, scope.rules_snapshot(ledger))
            tables["filter"] = original_filter
            tables["nat"] = original_nat.replace("-s 198.18.240.4/30", "-s 198.18.240.0/24")
            self.assertNotEqual(baseline, scope.rules_snapshot(ledger))
            self.assertNotEqual(canonical_rule(["-A", "FORWARD", "-s", "198.18.240.4/30", "-j", "ACCEPT"]),
                                canonical_rule(["-A", "FORWARD", "!", "-s", "198.18.240.4/30", "-j", "ACCEPT"]))


class CliTests(unittest.TestCase):
    def test_prepare_does_not_even_import_runner(self):
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp)
            case = path / "case.json"
            case.write_text(json.dumps(example()))
            with contextlib.redirect_stdout(io.StringIO()):
                cli.main(["prepare", "--config", str(case), "--out", str(path / "generated")], api=object())
            self.assertTrue((path / "generated/client-a/after/watch.sh").exists())

    def test_read_only_check_has_unverified_source_and_no_start(self):
        class Fake:
            def check(self, runner, requirements):
                self.requirements = requirements
                return {"ok": True, "identity": {"identity_verified": True, "zone_id": "example-az1"}}
        with tempfile.TemporaryDirectory() as temp:
            path = pathlib.Path(temp)
            case = path / "case.json"
            case.write_text(json.dumps(example()))
            fake = Fake()
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                cli.main(["check", "--config", str(case), "--client", "client-a", "--state-dir", str(path / "state")], api=fake)
            self.assertFalse(json.loads(output.getvalue())["case_source_verified"])
            self.assertTrue(fake.requirements["capture"])
            self.assertTrue(fake.requirements["forbid_az_overrides"])

    def test_baseline_adds_final_offsets_to_preserved_running_window(self):
        valid = ViewTests().business_frame()
        valid["window"]["cross"]["tx_bytes"] = 41
        live = dict(valid, sample_time="2026-11-10T10:01:00Z", retained_window=valid)
        live["window"] = {relation: {"tx_bytes": 0, "rx_bytes": 0} for relation in ("same", "cross", "unknown")}
        class FakeController:
            def snapshot(self, *args):
                return {"task_id": "watch", "frame_seq": 100, "frame_age_ms": 0, "last_frame": live}
            def evidence(self, frame):
                frame["target_next_offsets"] = {"t:0": 110}
                frame["drained"] = True
                return frame
            def path(self, *args):
                return "unused"
            def write(self, path, value):
                self.saved = value
        with tempfile.TemporaryDirectory() as temp:
            config = pathlib.Path(temp) / "case.json"
            config.write_text(json.dumps(example()))
            fake = FakeController()
            with patch.object(cli, "Controller", return_value=fake), contextlib.redirect_stdout(io.StringIO()):
                cli.main(["snapshot", "--config", str(config), "--client", "client-a"], api=object())
            self.assertEqual("2026-11-10T10:00:00Z", fake.saved["sample_time"])
            self.assertEqual(41, fake.saved["window"]["cross"]["tx_bytes"])
            self.assertEqual({"t:0": 110}, fake.saved["target_next_offsets"])


if __name__ == "__main__":
    unittest.main()
