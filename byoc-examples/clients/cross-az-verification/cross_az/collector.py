"""Single-interface TCP L3 capture. No payload is retained or logged."""
import argparse
import collections
import copy
import ctypes
import datetime
import ipaddress
import json
import os
import pathlib
import signal
import socket
import struct
import time


class CaptureDiagnostics:
    """Bounded safe classifications; never retain packet bodies or raw errors."""
    def __init__(self):
        self.kernel_packets = 0
        self.kernel_drops = 0
        self.overflows = 0
        self.error_codes = collections.Counter()

    def error(self, error):
        message = str(error)
        if message.startswith("Truncated"):
            code = "truncated_header"
        elif message.startswith("Invalid"):
            code = "invalid_header"
        elif message == "Kernel packet timestamp unavailable":
            code = "timestamp_unavailable"
        elif message == "Unsupported fragmented TCP packet":
            code = "fragmented_tcp_unsupported"
        elif message == "Unsupported IPv6 TCP capture path":
            code = "ipv6_tcp_unsupported"
        elif message == "Unsupported IPv6 extension budget":
            code = "ipv6_header_budget"
        elif message == "Unsupported IPv6 extension or protocol":
            code = "ipv6_extension_unsupported"
        elif message.startswith("Unsupported IPv6"):
            code = "ipv6_unsupported"
        else:
            code = "header_parse_error"
        self.error_codes[code] += 1

    def frame(self):
        return {"complete": not self.kernel_drops and not self.overflows and not self.error_codes,
                "kernel_packets": self.kernel_packets, "kernel_drops": self.kernel_drops,
                "syn_overflows": self.overflows, "parse_errors": sum(self.error_codes.values()),
                "error_codes": dict(self.error_codes)}


def ipv6_non_tcp(data, offset):
    """Exclude only confirmed non-TCP IPv6; unknown paths remain incomplete.

    This bounded header walk covers ordinary ICMPv6 ND/MLD control traffic,
    including MLD's hop-by-hop header. It does not enable IPv6 TCP accounting.
    """
    if len(data) < offset + 40:
        raise ValueError("Truncated IPv6 header")
    if data[offset] >> 4 != 6:
        raise ValueError("Invalid IPv6 header")
    payload_length = struct.unpack_from("!H", data, offset + 4)[0]
    if not payload_length:
        raise ValueError("Unsupported IPv6 jumbo path")
    end, cursor, protocol = offset + 40 + payload_length, offset + 40, data[offset + 6]
    extensions = 0
    while protocol in (0, 43, 60):
        if extensions >= 8:
            raise ValueError("Unsupported IPv6 extension budget")
        if cursor + 2 > min(len(data), end):
            raise ValueError("Truncated IPv6 extension header")
        length = (data[cursor + 1] + 1) * 8
        if cursor + length > min(len(data), end):
            raise ValueError("Truncated IPv6 extension header")
        protocol, cursor = data[cursor], cursor + length
        extensions += 1
    if protocol == 6:
        raise ValueError("Unsupported IPv6 TCP capture path")
    if protocol not in (17, 58, 59):
        raise ValueError("Unsupported IPv6 extension or protocol")
    if protocol in (17, 58) and cursor + 8 > min(len(data), end):
        raise ValueError("Truncated IPv6 non-TCP header")
    return None


def parse_packet(data, packet_type, timestamp=None, timestamp_source=None):
    """Decode Ethernet/IPv4/TCP headers, retaining header fields only."""
    if packet_type not in (0, 4):
        return None  # HOST/inbound or OUTGOING only; never count other copies.
    if len(data) < 14:
        raise ValueError("Truncated Ethernet header")
    ethertype = struct.unpack_from("!H", data, 12)[0]
    offset = 14
    if ethertype in (0x8100, 0x88a8):
        if len(data) < 18:
            raise ValueError("Truncated VLAN header")
        ethertype = struct.unpack_from("!H", data, 16)[0]
        offset = 18
    if ethertype == 0x86dd:
        return ipv6_non_tcp(data, offset)
    if ethertype != 0x0800:
        return None
    if len(data) < offset + 20:
        raise ValueError("Truncated IPv4 header")
    version_ihl, _, length, _, fragment, _, protocol = struct.unpack_from("!BBHHHBB", data, offset)
    ihl = (version_ihl & 15) * 4
    if version_ihl >> 4 != 4 or ihl < 20 or length < ihl:
        raise ValueError("Invalid IPv4 header")
    if protocol != 6:
        return None
    if fragment & 0x3fff:
        raise ValueError("Unsupported fragmented TCP packet")
    if length < ihl + 20 or len(data) < offset + ihl + 20:
        raise ValueError("Truncated TCP header")
    src = socket.inet_ntoa(data[offset + 12:offset + 16])
    dst = socket.inet_ntoa(data[offset + 16:offset + 20])
    tcp = offset + ihl
    sport, dport, seq = struct.unpack_from("!HHI", data, tcp)
    tcp_length = (data[tcp + 12] >> 4) * 4
    if tcp_length < 20 or length < ihl + tcp_length or len(data) < tcp + tcp_length:
        raise ValueError("Invalid TCP header length")
    return {"src": src, "dst": dst, "sport": sport, "dport": dport, "seq": seq,
            "syn": bool(data[tcp + 13] & 2), "ack": bool(data[tcp + 13] & 16),
            "direction": "tx" if packet_type == 4 else "rx", "bytes": length,
            "time": time.monotonic() if timestamp is None else timestamp,
            "timestamp_source": timestamp_source or "userspace"}


def verify_source(namespace_syns, host_syns, source_ip, endpoint, max_delta=2.0):
    """Match a fresh namespace SYN to ENI SYN; NAT may rewrite source port."""
    matches = []
    for ns in namespace_syns:
        if ns.get("timestamp_source") != "kernel" or not ns["syn"] or ns["ack"] or ns["direction"] != "tx" or (ns["dst"], ns["dport"]) != endpoint:
            continue
        candidates = [h for h in host_syns if h.get("timestamp_source") == "kernel" and h["syn"] and not h["ack"] and h["direction"] == "tx"
                      and (h["dst"], h["dport"], h["seq"]) == (ns["dst"], ns["dport"], ns["seq"])
                      and 0 <= h["time"] - ns["time"] <= max_delta]
        # Retransmissions with the same tuple are one connection; distinct ports are ambiguous.
        tuples = {(h["src"], h["sport"]) for h in candidates}
        if len(tuples) == 1 and next(iter(tuples))[0] == source_ip:
            matches.append({"namespace": ns, "eni": candidates[0]})
    unique = {(m["namespace"]["src"], m["namespace"]["sport"], m["namespace"]["seq"]) for m in matches}
    return {"verified": len(unique) == 1, "reason": "matched" if len(unique) == 1 else "source_unverified",
            "matches": matches if len(unique) == 1 else []}


def empty_counts():
    return {r: {"tx_bytes": 0, "rx_bytes": 0} for r in ("same", "cross", "unknown")}


class Window:
    def __init__(self, brokers, zone, seconds=10, clock=time.monotonic):
        self.endpoints = {(b["ip"], b["port"]): b["zone_id"] for b in brokers}
        self.zone, self.seconds, self.clock = zone, seconds, clock
        self.started = clock()
        self.events = collections.deque()
        self.errors = collections.deque()
        self.counts = empty_counts()
        self.peers = {}
        self.totals = empty_counts()
        self.sequence = 0
        self.max_events = 131072

    def _expire(self):
        cutoff = self.clock() - self.seconds
        while self.events and self.events[0][0] < cutoff:
            _, key, direction, size = self.events.popleft()
            self.peers[key][direction] -= size
            self.counts[key[3]][direction] -= size
            if not any(self.peers[key].values()):
                del self.peers[key]
        while self.errors and self.errors[0][0] < cutoff:
            self.errors.popleft()

    def add(self, packet):
        self._expire()
        tx = packet["direction"] == "tx"
        ip, port = (packet["dst"], packet["dport"]) if tx else (packet["src"], packet["sport"])
        zone = self.endpoints.get((ip, port))
        relation = "unknown" if zone is None else "same" if zone == self.zone else "cross"
        key = (ip, port, zone, relation)
        direction = "tx_bytes" if tx else "rx_bytes"
        self.totals[relation][direction] += packet["bytes"]
        if len(self.events) >= self.max_events or (key not in self.peers and len(self.peers) >= 8192):
            self.loss("queue_drops")
            return
        counts = self.peers.setdefault(key, {"tx_bytes": 0, "rx_bytes": 0})
        counts[direction] += packet["bytes"]
        self.counts[relation][direction] += packet["bytes"]
        self.events.append((self.clock(), key, direction, packet["bytes"]))

    def loss(self, key, count=1):
        self._expire()
        if count:
            now = self.clock()
            # Aggregate same-second losses at the latest timestamp so loss can
            # conservatively outlive the window, never expire prematurely.
            if self.errors and int(self.errors[-1][0]) == int(now):
                _, errors = self.errors.pop()
            else:
                errors = {}
            errors[key] = errors.get(key, 0) + count
            self.errors.append((now, errors))

    def frame(self, source_verified=False, scope_intact=False):
        self._expire()
        quality = {"kernel_drops": 0, "parse_errors": 0, "queue_drops": 0}
        for _, errors in self.errors:
            for key, count in errors.items():
                quality[key] += count
        quality.update(source_verified=source_verified, scope_intact=scope_intact)
        quality["complete"] = source_verified and scope_intact and not any(quality[k] for k in ("kernel_drops", "parse_errors", "queue_drops"))
        self.sequence += 1
        return {"schema_version": 1, "event": "network", "sample_seq": self.sequence,
                "sample_time": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "sample_mono_ms": int(self.clock() * 1000), "window_seconds": self.seconds,
                "elapsed_seconds": self.clock() - self.started, "quality": quality, "window": {k: dict(v) for k, v in self.counts.items()},
                "totals": {k: dict(v) for k, v in self.totals.items()}, "peers": [dict(ip=k[0], port=k[1], zone_id=k[2], relation=k[3], **v) for k, v in self.peers.items()]}


def capture_socket(interface):
    sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3))
    sock.bind((interface, 0))
    sock.setsockopt(socket.SOL_SOCKET, 35, 1)  # Linux SO_TIMESTAMPNS, common host clock.
    sock.settimeout(0.2)
    return sock


def receive(sock):
    data, ancillary, flags, address = sock.recvmsg(256, socket.CMSG_SPACE(struct.calcsize("ll")))
    for level, kind, value in ancillary:
        if level == socket.SOL_SOCKET and kind == 35 and len(value) >= struct.calcsize("ll"):
            seconds, nanos = struct.unpack_from("ll", value)
            return parse_packet(data, address[2], seconds + nanos / 1e9, "kernel")
    raise ValueError("Kernel packet timestamp unavailable")


def namespace_socket(namespace):
    """Create the socket in netns, restore host namespace before any checks."""
    libc = ctypes.CDLL(None, use_errno=True)
    original = os.open("/proc/self/ns/net", os.O_RDONLY)
    target = os.open("/var/run/netns/" + namespace, os.O_RDONLY)
    try:
        if libc.setns(target, 0) != 0:
            raise OSError(ctypes.get_errno(), "Cannot enter owned network namespace")
        try:
            return capture_socket("eth0")
        finally:
            if libc.setns(original, 0) != 0:
                raise OSError(ctypes.get_errno(), "Cannot restore host network namespace")
    finally:
        os.close(original)
        os.close(target)


def probe_capture(interface, duration):
    sock = capture_socket(interface)
    result = []
    diagnostics = CaptureDiagnostics()
    deadline = time.monotonic() + duration
    print(json.dumps({"event": "capture_ready"}), flush=True)
    while time.monotonic() < deadline:
        try:
            packet = receive(sock)
            if packet and packet["syn"] and not packet["ack"]:
                if len(result) < 2048:
                    result.append(packet)
                else:
                    diagnostics.overflows += 1
        except socket.timeout:
            pass
        except ValueError as error:
            diagnostics.error(error)
    diagnostics.kernel_packets, diagnostics.kernel_drops = struct.unpack("II", sock.getsockopt(263, 6, 8))
    sock.close()
    quality = diagnostics.frame()
    print(json.dumps({"syns": result, "complete": quality["complete"], "quality": quality}), flush=True)


class WorkloadReader:
    """Read only local task metrics. Reading never renews a task lease."""
    def __init__(self, spec, clock=time.monotonic, wall=time.time):
        self.spec, self.clock, self.wall = spec, clock, wall
        self.samples = {"produce": collections.deque(), "consume": collections.deque()}

    def frame(self):
        result = {"frames_fresh": True, "window_success": {}}
        now = self.clock()
        for role, task in self.spec["workload_task_ids"].items():
            path = pathlib.Path(self.spec["remote_root"]) / "state" / task / "metrics.json"
            samples = self.samples[role]
            fresh, frame = False, {}
            try:
                frame = json.loads(path.read_text())
                age = self.wall() - path.stat().st_mtime
                fresh = 0 <= age <= 15 and frame.get("event") in ("ready", "progress", "final")
                if frame.get("run_id") != self.spec["workload_run_id"] or frame.get("role") != role:
                    fresh = False
                if fresh and (not samples or samples[-1][1] != frame.get("sample_seq")):
                    samples.append((now, frame.get("sample_seq"), frame.get("messages", 0), frame.get("payload_bytes", 0)))
            except (OSError, ValueError):
                pass
            while len(samples) > 1 and samples[0][0] < now - self.spec["window_seconds"]:
                samples.popleft()
            if len(samples) >= 2:
                messages = samples[-1][2] - samples[0][2]
                payload = samples[-1][3] - samples[0][3]
            else:
                messages, payload = 0, 0
            result[role + "_active"] = fresh and messages > 0 and payload > 0
            result["window_success"][role] = {"messages": max(0, messages), "payload_bytes": max(0, payload),
                                                   "covered_seconds": samples[-1][0] - samples[0][0] if len(samples) >= 2 else 0}
            result[role + "_running"] = fresh and frame.get("state") == "running" and frame.get("event") == "progress"
            result["frames_fresh"] &= fresh
        return result


class RetainedWindow:
    """Freeze a valid business window while it is running, before final drain."""
    def __init__(self, warmup_seconds):
        self.warmup_seconds, self.value = warmup_seconds, None

    def update(self, frame):
        from .view import observation
        workload = frame.get("workload", {})
        state, _ = observation(frame, 0, workload, self.warmup_seconds)
        covered = min((workload.get("window_success", {}).get(role, {}).get("covered_seconds", 0) for role in ("produce", "consume")), default=0)
        if state == "observing" and all(workload.get(role + "_running") for role in ("produce", "consume")) and covered >= max(0.5, frame["window_seconds"] - 2):
            self.value = copy.deepcopy(frame)
            self.value["capture_frame_age_ms"] = 0
            self.value["warmup_seconds"] = self.warmup_seconds
        return copy.deepcopy(self.value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec-json")
    parser.add_argument("--probe-interface")
    parser.add_argument("--duration", type=float, default=4)
    args = parser.parse_args()
    if args.probe_interface:
        return probe_capture(args.probe_interface, args.duration)
    spec = json.loads(args.spec_json)
    from .scope import Scope
    scope = Scope(spec)
    ledger = scope.read()
    window = Window(spec["brokers"], spec["zone_id"], spec["window_seconds"])
    workload = WorkloadReader(spec)
    retained = RetainedWindow(spec["warmup_seconds"])
    sock = namespace_socket(ledger["namespace"])
    previous = 0
    stopping = [False]
    previous_handlers = {}
    for signum in (signal.SIGTERM, signal.SIGINT):
        previous_handlers[signum] = signal.signal(signum, lambda *_: stopping.__setitem__(0, True))
    frame = None
    try:
        while not stopping[0]:
            try:
                packet = receive(sock)
                if packet:
                    window.add(packet)
            except socket.timeout:
                pass
            except ValueError:
                window.loss("parse_errors")
            if time.monotonic() - previous >= 1:
                # Reading PACKET_STATISTICS resets the kernel counters.
                _, drops = struct.unpack("II", sock.getsockopt(263, 6, 8))
                window.loss("kernel_drops", drops)
                intact = scope.intact(ledger)
                if not intact and ledger.get("source_proof", {}).get("verified"):
                    scope.invalidate_source(ledger)
                proof = ledger.get("source_proof", {}).get("verified", False)
                frame = window.frame(proof, intact)
                frame.update(run_id=spec["run_id"], client_id=spec["client_id"], phase=spec["phase"],
                             scope_id=spec["scope_id"], actual_zone_id=spec["zone_id"], workload=workload.frame(),
                             actual_hostname=spec.get("actual_hostname"), actual_instance_id=spec.get("actual_instance_id"),
                             source_ip=spec["source_ip"], workload_task_ids=spec["workload_task_ids"])
                frame["retained_window"] = retained.update(frame)
                print(json.dumps(frame), flush=True)
                previous = time.monotonic()
    finally:
        sock.close()
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
    if frame:
        frame.update(event="final", role="watch", exit_code=0, state="stopped", sample_seq=frame["sample_seq"] + 1)
        print(json.dumps(frame), flush=True)


if __name__ == "__main__":
    main()
