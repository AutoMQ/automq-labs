"""Validated physical topology and local-only command generation."""
import hashlib
import ipaddress
import json
import math
import pathlib
import re
import shlex


class CaseError(ValueError):
    pass


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
        raise CaseError("Invalid identifier")
    return value


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def positive(value, name, maximum=None):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0 or (maximum and value > maximum):
        raise CaseError("Invalid " + name)
    return value


def load(path):
    path = pathlib.Path(path).resolve()
    try:
        value = json.loads(path.read_text())
        validate(value)
    except CaseError:
        raise
    except (OSError, json.JSONDecodeError, TypeError, KeyError, ValueError):
        raise CaseError("Invalid case file; check schema, physical addresses and input paths") from None
    for client in value["clients"].values():
        client["runner_file"] = str((path.parent / client["runner_file"]).resolve())
    return value


def validate(case):
    def keys(value, allowed):
        if not isinstance(value, dict) or set(value) - set(allowed):
            raise CaseError("Unsupported schema fields; secrets belong only in remote properties")
    keys(case, ("schema_version", "run_id", "topic", "workload", "observation", "clients", "brokers"))
    if case.get("schema_version") != 1:
        raise CaseError("Expected schema_version=1")
    identifier(case["run_id"])
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,200}", case["topic"]) or case["topic"] in (".", ".."):
        raise CaseError("Invalid topic")
    workload = case["workload"]
    keys(workload, ("partitions", "rate_mibps", "record_bytes", "compression", "duration_seconds", "max_messages", "max_errors"))
    for key in ("partitions", "record_bytes"):
        if type(workload[key]) is not int:
            raise CaseError("Expected integer " + key)
        positive(workload[key], key)
    positive(workload["rate_mibps"], "rate_mibps")
    for key in ("duration_seconds", "max_messages", "max_errors"):
        if key in workload:
            positive(workload[key], key)
            if key != "duration_seconds" and type(workload[key]) is not int:
                raise CaseError("Expected integer workload limit")
    if workload["compression"] not in ("none", "gzip", "snappy", "lz4", "zstd"):
        raise CaseError("Unsupported compression")
    observation = case.setdefault("observation", {})
    keys(observation, ("window_seconds", "warmup_seconds"))
    positive(observation.setdefault("window_seconds", 10), "window_seconds", 3600)
    warmup = observation.setdefault("warmup_seconds", 10)
    if type(warmup) not in (int, float) or not math.isfinite(warmup) or warmup < 0:
        raise CaseError("Invalid warmup_seconds")
    if not case["clients"] or not case["brokers"]:
        raise CaseError("Clients and physical brokers are required")
    prefixes = {}
    for client_id, client in case["clients"].items():
        keys(client, ("runner_file", "remote_connection_file", "zone_id", "source_ip", "source_cidrs", "scope_cidr"))
        identifier(client_id)
        identifier(client["zone_id"])
        if not isinstance(client["runner_file"], str) or not client["runner_file"]:
            raise CaseError("runner_file is required")
        if not pathlib.PurePosixPath(client["remote_connection_file"]).is_absolute() or "\n" in client["remote_connection_file"]:
            raise CaseError("remote_connection_file must be an absolute remote path")
        source = ipaddress.ip_address(client["source_ip"])
        if source.version != 4:
            raise CaseError("IPv6 source is unsupported")
        pool = ipaddress.ip_network(client["scope_cidr"], strict=True)
        if pool.version != 4 or pool.prefixlen != 24:
            raise CaseError("scope_cidr must be an IPv4 /24 allocation pool")
        networks = [ipaddress.ip_network(cidr, strict=True) for cidr in client["source_cidrs"]]
        if not networks or any(net.version != 4 for net in networks):
            raise CaseError("IPv4 source CIDRs are required")
        if not any(source in net for net in networks):
            raise CaseError("source_ip does not match source_cidrs")
        if any(pool.overlaps(net) for net in networks):
            raise CaseError("Scope allocation pool overlaps source CIDRs")
        for network in networks:
            key = str(network)
            previous = prefixes.setdefault(key, client["zone_id"])
            if previous != client["zone_id"]:
                raise CaseError("Conflicting zones for identical CIDR prefix")
    for client in case["clients"].values():
        if longest_prefix(client["source_ip"], prefixes) != client["zone_id"]:
            raise CaseError("Longest-prefix source mapping differs from client zone")
    endpoints = {}
    for broker in case["brokers"]:
        keys(broker, ("ip", "port", "zone_id", "rack"))
        address = ipaddress.ip_address(broker["ip"])
        if address.version != 4 or type(broker["port"]) is not int or not 1 <= broker["port"] <= 65535:
            raise CaseError("Invalid physical IPv4 broker endpoint")
        identifier(broker["zone_id"])
        if broker.get("rack") != broker["zone_id"]:
            raise CaseError("Broker rack must match physical zone_id")
        endpoint = (broker["ip"], broker["port"])
        if endpoint in endpoints and endpoints[endpoint] != broker["zone_id"]:
            raise CaseError("Conflicting physical broker endpoint")
        endpoints[endpoint] = broker["zone_id"]
    return case


def longest_prefix(address, mapping):
    address = ipaddress.ip_address(address)
    matching = [(ipaddress.ip_network(prefix).prefixlen, zone) for prefix, zone in mapping.items()
                if address in ipaddress.ip_network(prefix)]
    return max(matching)[1] if matching else None


def topology(case):
    zones = {}
    warnings = ["source_unverified: candidate topology is not ENI/AZ/source proof",
                "Product multi-AZ routing capability, WAL mode, original leader distribution and network reachability require verification"]
    broker_zones = {broker["zone_id"] for broker in case["brokers"]}
    for client_id, client in case["clients"].items():
        zones.setdefault(client["zone_id"], set()).update(client["source_cidrs"])
        if client["zone_id"] not in broker_zones:
            warnings.append(client_id + ": no same-AZ physical broker")
    value = "<>".join(zone + "@" + ",".join(sorted(cidrs)) for zone, cidrs in sorted(zones.items()))
    return {"zone_cidr": value, "warnings": warnings, "client_zones": sorted(zones),
            "coverage": "three-zone candidates" if len(zones) == 3 else "partial-zone candidates"}


def prepare(case, config_path, out, clients=None, executable=None):
    """Only write local files. Never contact AWS, Kafka or a runner."""
    selected = list(clients or case["clients"])
    if not selected or len(set(selected)) != len(selected) or any(c not in case["clients"] for c in selected):
        raise CaseError("Invalid selected cohort")
    out = pathlib.Path(out)
    if out.exists() and any(out.iterdir()):
        raise CaseError("Output directory must be empty; preserve previous phase state")
    out.mkdir(parents=True, exist_ok=True, mode=0o700)
    out.chmod(0o700)
    report = topology(case)
    (out / "zone-cidr.txt").write_text(report["zone_cidr"] + "\n")
    (out / "cohort.json").write_text(json.dumps({"schema_version": 1, "run_id": case["run_id"], "clients": selected}) + "\n")
    executable = str(pathlib.Path(executable or pathlib.Path(__file__).parent.parent / "az-case").resolve())
    base = [executable, "--config", str(pathlib.Path(config_path).resolve()), "--state-dir", str((out / "state").resolve()), "--cohort", ",".join(selected)]
    for client_id in selected:
        for phase in ("before", "after"):
            target = out / client_id / phase
            target.mkdir(parents=True, mode=0o700)
            for role in ("check", "runtime-prepare", "watch", "consume", "produce", "runtime-cleanup"):
                argv = [base[0], role] + base[1:] + ["--client", client_id, "--phase", phase]
                script = target / (role + ".sh")
                script.write_text("#!/bin/sh\nset -eu\nexec " + shlex.join(argv) + '\n')
                script.chmod(0o700)
    (out / "preparation.json").write_text(json.dumps(report, indent=2) + "\n")
    first = selected[0]
    client = case["clients"][first]
    runner_entry = pathlib.Path(__file__).resolve().parents[4] / "tools" / "kafka-workload" / "run-remote"
    task = "az-topic-" + fingerprint({"run": case["run_id"], "client": first})[:24]
    argv = [str(runner_entry), "--runner", client["runner_file"], "--state-dir", str((out / "state").resolve()), "start", "--task-id", task,
            "--role", "topic", "--run-id", case["run_id"], "--", "topic", "create", "--config", client["remote_connection_file"],
            "--topic", case["topic"], "--partitions", str(case["workload"]["partitions"])]
    (out / "topic-command.txt").write_text("Explicit topic preparation (no topic was created):\n" + shlex.join(argv) + "\n")
    (out / "topic-create.sh").write_text("#!/bin/sh\nset -eu\nexec " + shlex.join(argv) + "\n")
    (out / "topic-create.sh").chmod(0o700)
    return report


def aws_candidates(profile, region, invoke):
    """Read-only discovery. Candidate addresses never constitute source proof."""
    argv = ["aws", "--profile", profile, "--region", region, "ec2", "describe-network-interfaces", "--output", "json"]
    result = invoke(argv)
    return {"schema_version": 1, "verified": False, "network_interfaces": json.loads(result)["NetworkInterfaces"]}
