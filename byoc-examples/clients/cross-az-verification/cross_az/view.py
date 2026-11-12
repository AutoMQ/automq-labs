"""Conservative frame freshness, business progress, offsets and comparisons."""
import copy
import time


class Freshness:
    def __init__(self, clock=time.monotonic):
        self.clock, self.frames = clock, {}

    def age(self, snapshot, rtt=0):
        key = snapshot["task_id"]
        sequence = snapshot.get("frame_seq")
        current = self.clock()
        old = self.frames.get(key)
        reported = snapshot.get("frame_age_ms")
        age = float("inf") if reported is None else max(0, reported / 1000) + max(0, rtt)
        if old and old[0] == sequence:
            age = max(age, old[2] + current - old[1])
        self.frames[key] = (sequence, current, age)
        return age


def targets(producer_finals):
    merged = {}
    for frame in producer_finals:
        if frame.get("event") != "final" or frame.get("unconfirmed_messages", 0) or frame.get("errors", 0):
            return {}, "Producer final is missing or has unconfirmed writes/errors"
        for partition, offset in frame.get("max_acked_offsets", {}).items():
            merged[partition] = max(merged.get(partition, -1), offset)
    return {partition: offset + 1 for partition, offset in merged.items()}, None if merged else "No successfully acknowledged writes"


def drained(next_offsets, target_offsets):
    return bool(target_offsets) and all(next_offsets.get(p, -1) >= offset for p, offset in target_offsets.items())


def ready_barrier(snapshots, partitions, topic, run_id=None):
    missing = []
    expected = {topic + ":" + str(p) for p in range(partitions)}
    for client, snap in snapshots.items():
        ready = snap.get("ready_frame") or snap.get("last_frame", {})
        if snap.get("state") not in ("ready", "running") or snap.get("frame_age_ms") is None or snap["frame_age_ms"] > 15000 or ready.get("event") != "ready" or set(ready.get("start_offsets", {})) != expected or (run_id is not None and ready.get("run_id") != run_id):
            missing.append(client)
    return missing


class Progress:
    def __init__(self, clock=time.monotonic):
        self.clock, self.history = clock, {}

    def active(self, key, frame, fresh, window_seconds):
        now = self.clock()
        samples = self.history.setdefault(key, [])
        if fresh and frame.get("event") in ("progress", "final"):
            sample = (now, frame.get("sample_seq"), frame.get("messages", 0), frame.get("payload_bytes", 0))
            if not samples or sample[1] != samples[-1][1]:
                samples.append(sample)
        # Keep the immediately preceding sample to measure the whole window.
        while len(samples) > 2 and samples[1][0] < now - window_seconds:
            samples.pop(0)
        if not fresh or len(samples) < 2 or now - samples[-1][0] > 15:
            return False
        first, last = samples[0], samples[-1]
        return last[2] > first[2] and last[3] > first[3] and last[0] >= now - window_seconds


def observation(frame, age_seconds, workload, warmup_seconds=10):
    quality = frame.get("quality", {})
    if age_seconds > 15:
        return "stale", "Remote frame stale; zero-byte conclusion unavailable"
    if not quality.get("complete") or not quality.get("source_verified") or not quality.get("scope_intact") or any(quality.get(k, 0) for k in ("kernel_drops", "parse_errors", "queue_drops")):
        return "incomplete", "Capture/source/scope incomplete; zero-byte conclusion unavailable"
    if frame.get("elapsed_seconds", 0) < max(warmup_seconds, frame.get("window_seconds", 0)):
        return "warming", "Waiting for a full independent observation window"
    if not workload.get("produce_active") or not workload.get("consume_active") or not workload.get("frames_fresh"):
        return "waiting", "Waiting for successful producer and consumer progress"
    window = frame["window"]
    if sum(window["unknown"].values()):
        return "incomplete", "Unknown TCP peers observed; zero-byte conclusion unavailable"
    if sum(window["cross"].values()):
        return "observing", "Cross-AZ bytes observed in this window"
    if not sum(window["same"].values()):
        return "incomplete", "No captured successful workload path; zero-byte conclusion unavailable"
    return "observing", "No cross-AZ TCP traffic observed in this window (client scope, L3 bytes)"


def compare(baseline, current):
    reasons = []
    for key in ("topology_fingerprint", "workload_fingerprint", "window_seconds", "cohort"):
        if baseline.get(key) != current.get(key):
            reasons.append(key + " differs")
    if not sum(baseline.get("window", {}).get("cross", {}).values()):
        reasons.append("Baseline has no cross-AZ distinction")
    for label, value in (("before", baseline), ("after", current)):
        quality = value.get("quality", {})
        if not quality.get("complete") or not quality.get("source_verified") or not quality.get("scope_intact"):
            reasons.append(label + " capture/source incomplete")
        if sum(value.get("window", {}).get("unknown", {}).values()):
            reasons.append(label + " has unknown peers")
        if not value.get("drained"):
            reasons.append(label + " offset boundary incomplete")
        if not value.get("successful_messages") or not value.get("successful_payload_bytes"):
            reasons.append(label + " has no successful business traffic")
        workload = value.get("workload", {})
        state, _ = observation(value, value.get("capture_frame_age_ms", float("inf")) / 1000,
                               workload, value.get("warmup_seconds", 10))
        if state != "observing":
            reasons.append(label + " window was not fresh, warm and carrying successful business traffic")
        for role in ("produce", "consume"):
            success = workload.get("window_success", {}).get(role, {})
            if not success.get("messages") or not success.get("payload_bytes") or success.get("covered_seconds", 0) < max(0.5, value.get("window_seconds", 0) - 2):
                reasons.append(label + " " + role + " window success/coverage incomplete")
    # Exact equality is intentionally conservative. Unequal runs are shown with
    # their raw bytes rather than manufacturing a percentage improvement.
    for key in ("successful_messages", "successful_payload_bytes", "partition_coverage"):
        if baseline.get(key) != current.get(key):
            reasons.append("Actual " + key + " differs")
    for role in ("produce", "consume"):
        for key in ("messages", "payload_bytes"):
            before = baseline.get("workload", {}).get("window_success", {}).get(role, {}).get(key)
            after = current.get("workload", {}).get("window_success", {}).get(role, {}).get(key)
            if before != after:
                reasons.append("Actual window " + role + " " + key + " differs")
    return {"comparable": not reasons, "reasons": reasons,
            "before_cross": copy.deepcopy(baseline.get("window", {}).get("cross")),
            "after_cross": copy.deepcopy(current.get("window", {}).get("cross"))}


def render(frame, age_seconds, workload, warmup_seconds=10, baseline=None):
    state, message = observation(frame, age_seconds, workload, warmup_seconds)
    terminal = frame.get("role_states", {}).get("watch") in ("stopped", "failed")
    if terminal:
        state, message = "stopped", "Watch stopped; displayed bytes belong to its historical final sample"
    label = "HISTORICAL final window" if terminal else "STALE last window" if state == "stale" else "LIVE window"
    lines = ["Client {} | Actual AZ {} | Phase {} | Scope {}".format(frame.get("client_id"), frame.get("actual_zone_id"), frame.get("phase"), frame.get("scope_id")),
             "Target {} | Actual host {} | ENI source {} | Watch task {}".format(frame.get("actual_instance_id") or frame.get("identity", {}).get("instance_id", "unverified"), frame.get("actual_hostname") or frame.get("identity", {}).get("hostname", "unverified"), frame.get("source_ip", "unverified"), frame.get("task_id", "unverified")),
             "Roles {}".format(frame.get("role_states", {})),
             "State {} | Remote frame {} | Age {:.2f}s | Window {}s".format(state, frame.get("sample_seq"), age_seconds, frame.get("window_seconds")),
             "Sample {} | {} | L3 B/s from bytes/window seconds".format(frame.get("sample_time"), label),
             "Physical peer             AZ             Relation    TX bytes/rate       RX bytes/rate"]
    for role in ("produce", "consume"):
        success = workload.get("window_success", {}).get(role, {})
        lines.append("{} window success {} messages | {} payload B | task {}".format(role, success.get("messages", "?"), success.get("payload_bytes", "?"), frame.get("workload_task_ids", {}).get(role, "unverified")))
    for peer in frame.get("peers", []):
        duration = max(float(frame.get("window_seconds", 0)), 0.001)
        lines.append("{}:{} {} {} TX {} B ({:.3f} B/s) RX {} B ({:.3f} B/s)".format(peer["ip"], peer["port"], peer.get("zone_id") or "Unknown", peer["relation"], peer["tx_bytes"], peer["tx_bytes"] / duration, peer["rx_bytes"], peer["rx_bytes"] / duration))
    for relation in ("same", "cross", "unknown"):
        counts = frame.get("window", {}).get(relation, {})
        totals = frame.get("totals", {}).get(relation, {})
        lines.append("{} window TX {} B RX {} B | total TX {} B RX {} B".format(relation, counts.get("tx_bytes", "?"), counts.get("rx_bytes", "?"), totals.get("tx_bytes", "?"), totals.get("rx_bytes", "?")))
    lines.extend(["Quality " + str(frame.get("quality", {})), message, "IP L3 total length, including TCP headers/retransmissions; not cloud billing or Kafka payload bytes."])
    if baseline:
        lines.append("HISTORICAL before sample {} cross bytes: {}".format(baseline.get("sample_time"), baseline.get("window", {}).get("cross")))
        lines.append("HISTORICAL before successful window: " + str(baseline.get("workload", {}).get("window_success", {})))
        retained = frame.get("retained_window")
        if retained:
            lines.append("HISTORICAL after sample {} cross bytes: {}".format(retained.get("sample_time"), retained.get("window", {}).get("cross")))
            lines.append("HISTORICAL after successful window: " + str(retained.get("workload", {}).get("window_success", {})))
            result = compare(baseline, retained)
            lines.append("Comparable retained windows" if result["comparable"] else "Not comparable: " + "; ".join(result["reasons"]))
        else:
            lines.append("Not comparable: no valid after business window retained")
    return "\n".join(lines)
