"""Explicit root-only network namespace lifecycle with an ownership ledger."""
import argparse
import collections
import contextlib
import fcntl
import hashlib
import ipaddress
import json
import os
import pathlib
import shlex
import shutil
import socket
import struct
import subprocess
import sys
import time

from .config import CaseError, fingerprint, identifier


def execute(argv):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise CaseError("Scope command failed: " + argv[0])
    return result.stdout


def atomic(path, value):
    temp = path.with_suffix(".tmp")
    descriptor = os.open(str(temp), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as stream:
        json.dump(value, stream, sort_keys=True)
    os.replace(str(temp), str(path))


def canonical_rule(argv):
    """Normalize iptables' selector reordering without dropping any match.

    iptables-save emits source/destination selectors before interfaces even
    when installation used another order. Keep every selector (including
    negation and duplicates), and keep all remaining match/target tokens.
    """
    argv = tuple(argv)
    selectors, remainder, index = [], [], 2
    while index < len(argv):
        negation = argv[index] == "!"
        option_index = index + 1 if negation else index
        if option_index < len(argv) and argv[option_index] in ("-s", "-d", "-i", "-o") and option_index + 1 < len(argv):
            option, value = argv[option_index:option_index + 2]
            if option in ("-s", "-d"):
                value = str(ipaddress.ip_network(value, strict=False))
            selectors.append((option, negation, value))
            index = option_index + 2
        elif argv[index] == "--ctstate" and index + 1 < len(argv):
            remainder.extend((argv[index], ",".join(sorted(argv[index + 1].split(",")))))
            index += 2
        else:
            remainder.append(argv[index])
            index += 1
    return argv[:2], tuple(sorted(selectors)), tuple(remainder)


class Scope:
    def __init__(self, spec, run=execute, root=None):
        self.spec, self.run = spec, run
        identifier(spec["scope_id"])
        root = pathlib.Path(root or spec["remote_root"])
        if not root.is_absolute() or ".." in root.parts or root == pathlib.Path("/"):
            raise CaseError("Invalid scope state root")
        self.root = root / "state" / "scopes"
        self.path = self.root / (spec["scope_id"] + ".json")
        token = hashlib.sha256(spec["scope_id"].encode()).hexdigest()[:10]
        self.ns, self.veth = "az-" + token, "azh" + token
        self.nat, self.forward = "AZN" + token, "AZF" + token
        self.comment = "automq-az:" + token

    def read(self):
        value = json.loads(self.path.read_text())
        if value["owner"] != self.spec["scope_id"] or value["namespace"] != self.ns:
            raise CaseError("Scope ownership mismatch")
        return value

    @contextlib.contextmanager
    def lock(self):
        if os.geteuid() != 0:
            raise CaseError("Explicit runtime preparation requires root")
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.root.is_symlink() or self.root.stat().st_uid != 0 or self.root.stat().st_mode & 0o077:
            raise CaseError("Scope ledger directory must be root-owned mode 0700")
        with open(self.root / ".lock", "a") as lock:
            os.chmod(str(self.root / ".lock"), 0o600)
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def _iptables(self, table, chain, rule):
        return ["iptables", "-w", "5", "-t", table, "-A", chain] + rule

    def rules_snapshot(self, ledger):
        """Track only reachable traffic paths; ignore verified disjoint scopes.

        Other scopes can append their exact owned jumps without invalidating
        this scope. An overlapping/broad rule, policy or reachable chain change
        remains relevant and invalidates the source proof.
        """
        ignored = {"nat": collections.Counter(), "filter": collections.Counter()}
        ours = ipaddress.ip_network(ledger["subnet"])
        for path in self.root.glob("*.json"):
            if path == self.path:
                continue
            other = json.loads(path.read_text())
            if not other.get("subnet") or ours.overlaps(ipaddress.ip_network(other["subnet"])):
                continue
            token = hashlib.sha256(other.get("owner", "").encode()).hexdigest()[:10]
            if other.get("namespace") != "az-" + token or other.get("veth") != "azh" + token:
                continue
            for command in other.get("rules", []):
                # Trust only exact ledger commands with the owner's comment
                # and subnet. Broad rules never qualify for exclusion.
                if len(command) > 8 and command[:4] == ["iptables", "-w", "5", "-t"] and command[5] == "-A" and "automq-az:" + token in command and other["subnet"] in command:
                    ignored[command[4]][canonical_rule(command[5:])] += 1
        result = []
        for table, root in (("nat", "POSTROUTING"), ("filter", "FORWARD")):
            definitions, rules = {}, {}
            for line in self.run(["iptables-save", "-t", table]).splitlines():
                if line.startswith(":"):
                    parts = line[1:].split()
                    definitions[parts[0]] = tuple(parts[:2])
                elif line.startswith("-A "):
                    argv = tuple(shlex.split(line))
                    canonical = canonical_rule(argv)
                    if ignored[table][canonical]:
                        ignored[table][canonical] -= 1
                    else:
                        rules.setdefault(argv[1], []).append(argv)
            reachable, pending = set(), [root]
            while pending:
                chain = pending.pop()
                if chain in reachable:
                    continue
                reachable.add(chain)
                for rule in rules.get(chain, []):
                    for flag in ("-j", "-g"):
                        if flag in rule:
                            target = rule[rule.index(flag) + 1]
                            if target in definitions:
                                pending.append(target)
            result.append({chain: {"policy": definitions.get(chain), "rules": rules.get(chain, [])} for chain in sorted(reachable)})
        return result

    def _allocate(self, routes):
        pool = ipaddress.ip_network(self.spec["scope_cidr"], strict=True)
        if pool.version != 4 or pool.prefixlen != 24:
            raise CaseError("scope_cidr must be an IPv4 /24 pool")
        used = []
        for path in self.root.glob("*.json"):
            other = json.loads(path.read_text())
            if other.get("subnet"):
                used.append(ipaddress.ip_network(other["subnet"]))
        # Any pre-existing host route in the pool is a conflict, including a
        # broad VPC route. The default route is the sole expected exception.
        for route in routes:
            if route.get("dst", "default") != "default":
                used.append(ipaddress.ip_network(route["dst"], strict=False))
        candidates = list(pool.subnets(new_prefix=30))
        start = int(hashlib.sha256(self.spec["scope_id"].encode()).hexdigest(), 16) % len(candidates)
        for index in range(len(candidates)):
            network = candidates[(start + index) % len(candidates)]
            if not any(network.overlaps(other) for other in used):
                return network
        raise CaseError("scope_cidr conflicts with existing routes or owned scopes")

    def wait_for_dad(self, timeout=5, clock=time.monotonic, sleep=time.sleep):
        """Observe normal namespace-local DAD; never alter IPv6 settings."""
        deadline = clock() + timeout
        while True:
            addresses = json.loads(self.run(["ip", "-n", self.ns, "-j", "addr", "show"]))
            flags = [info for link in addresses for info in link.get("addr_info", []) if info.get("family") == "inet6"]
            if any(info.get("dadfailed") for info in flags):
                raise CaseError("Namespace IPv6 duplicate-address detection failed")
            if not any(info.get("tentative") for info in flags):
                return
            if clock() >= deadline:
                raise CaseError("Namespace IPv6 duplicate-address detection timed out")
            sleep(min(0.1, max(0, deadline - clock())))

    def prepare(self):
        with self.lock():
            if self.path.exists():
                ledger = self.read()
                if ledger["spec_fingerprint"] != fingerprint(self.spec) or not self.intact(ledger, locked=True):
                    raise CaseError("Existing scope differs or has drifted; inspect before cleanup")
                return ledger
            for tool in ("ip", "iptables"):
                if not shutil.which(tool):
                    raise CaseError("Required Linux tool missing: " + tool)
            if pathlib.Path("/proc/sys/net/ipv4/ip_forward").read_text().strip() != "1":
                raise CaseError("ip_forward must already be 1; arrange host forwarding explicitly before retrying")
            route = json.loads(self.run(["ip", "-j", "route", "get", self.spec["brokers"][0]["ip"]]))[0]
            interface = route.get("dev")
            source = route.get("prefsrc", route.get("src"))
            if not interface or source != self.spec["source_ip"]:
                raise CaseError("Configured source_ip differs from selected host ENI route")
            if not self.spec.get("identity_verified") or self.spec.get("actual_zone_id") != self.spec["zone_id"]:
                raise CaseError("Real ENI/AZ identity is unverified; run remote check first")
            subnet = self._allocate(json.loads(self.run(["ip", "-j", "route", "show", "table", "all"])))
            host_ip, ns_ip = str(subnet[1]), str(subnet[2])
            # Refuse collisions before recording any destructive inverse.
            names = self.run(["ip", "netns", "list"])
            links = json.loads(self.run(["ip", "-j", "link", "show"]))
            if self.ns in names.split() or any(link["ifname"] == self.veth for link in links):
                raise CaseError("Unowned namespace or interface collision")
            for table, chain in (("nat", self.nat), ("filter", self.forward)):
                if (":" + chain + " ") in self.run(["iptables-save", "-t", table]):
                    raise CaseError("Unowned iptables chain collision")
            resolver = pathlib.Path("/etc/netns") / self.ns
            if resolver.exists() or resolver.is_symlink():
                raise CaseError("Unowned resolver path collision")
            ledger = {"schema_version": 1, "owner": self.spec["scope_id"], "namespace": self.ns,
                      "veth": self.veth, "subnet": str(subnet), "source_ip": source, "interface": interface,
                      "spec_fingerprint": fingerprint(self.spec), "undo": [], "state": "preparing"}
            atomic(self.path, ledger)
            def apply(argv, undo=None):
                self.run(argv)
                if undo:
                    ledger["undo"].append(undo)
                    atomic(self.path, ledger)
            try:
                apply(["ip", "netns", "add", self.ns], ["ip", "netns", "delete", self.ns])
                apply(["ip", "link", "add", self.veth, "type", "veth", "peer", "name", "eth0", "netns", self.ns], ["ip", "link", "delete", self.veth])
                apply(["ip", "link", "set", self.veth, "alias", self.comment])
                apply(["ip", "addr", "add", host_ip + "/30", "dev", self.veth])
                apply(["ip", "link", "set", self.veth, "up"])
                for args in (["link", "set", "lo", "up"], ["link", "set", "eth0", "up"],
                             ["addr", "add", ns_ip + "/30", "dev", "eth0"], ["route", "add", "default", "via", host_ip]):
                    apply(["ip", "-n", self.ns] + args)
                resolver.mkdir(parents=True, mode=0o755)
                # Resolver is explicit owned state, never rewrite host resolv.conf.
                resolver_bytes = pathlib.Path("/etc/resolv.conf").read_bytes()
                ledger["resolver_sha256"] = hashlib.sha256(resolver_bytes).hexdigest()
                ledger["resolver"] = str(resolver)
                atomic(self.path, ledger)
                (resolver / "resolv.conf").write_bytes(resolver_bytes)
                for table, chain in (("nat", self.nat), ("filter", self.forward)):
                    apply(["iptables", "-w", "5", "-t", table, "-N", chain], ["iptables", "-w", "5", "-t", table, "-X", chain])
                rules = [
                    ("nat", self.nat, ["-s", str(subnet), "-o", interface, "-m", "comment", "--comment", self.comment, "-j", "SNAT", "--to-source", source]),
                    ("nat", "POSTROUTING", ["-s", str(subnet), "-o", interface, "-m", "comment", "--comment", self.comment, "-j", self.nat]),
                    ("filter", self.forward, ["-i", self.veth, "-s", str(subnet), "-o", interface, "-m", "comment", "--comment", self.comment, "-j", "ACCEPT"]),
                    ("filter", self.forward, ["-i", interface, "-o", self.veth, "-d", str(subnet), "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-m", "comment", "--comment", self.comment, "-j", "ACCEPT"]),
                    ("filter", "FORWARD", ["-i", self.veth, "-s", str(subnet), "-m", "comment", "--comment", self.comment, "-j", self.forward]),
                    ("filter", "FORWARD", ["-o", self.veth, "-d", str(subnet), "-m", "comment", "--comment", self.comment, "-j", self.forward])]
                ledger["rules"] = []
                for table, chain, rule in rules:
                    command = self._iptables(table, chain, rule)
                    inverse = command[:]
                    inverse[5] = "-D"
                    apply(command, inverse)
                    ledger["rules"].append(command)
                ledger["route_fingerprint"] = fingerprint(json.loads(self.run(["ip", "-j", "route", "get", self.spec["brokers"][0]["ip"]])))
                ledger["rules_fingerprint"] = fingerprint(self.rules_snapshot(ledger))
                self.wait_for_dad()
                ledger["namespace_fingerprint"] = fingerprint([self.run(["ip", "-n", self.ns, "-j", kind, "show"]) for kind in ("addr", "route")])
                ledger["source_proof"] = self.prove(ledger)
                ledger["state"] = "prepared"
                atomic(self.path, ledger)
                return ledger
            except Exception:
                self._rollback(ledger)
                raise

    def intact(self, ledger, locked=False):
        try:
            if not locked:
                with open(self.root / ".lock", "r") as lock:
                    fcntl.flock(lock, fcntl.LOCK_SH)
                    return self.intact(ledger, locked=True)
            links = json.loads(self.run(["ip", "-j", "link", "show", self.veth]))
            if len(links) != 1 or links[0].get("ifalias") != self.comment:
                return False
            if pathlib.Path("/proc/sys/net/ipv4/ip_forward").read_text().strip() != "1":
                return False
            for command in ledger["rules"]:
                check = command[:]
                check[5] = "-C"
                self.run(check)
            route = json.loads(self.run(["ip", "-j", "route", "get", self.spec["brokers"][0]["ip"]]))
            if fingerprint(route) != ledger["route_fingerprint"]:
                return False
            if fingerprint(self.rules_snapshot(ledger)) != ledger["rules_fingerprint"]:
                return False
            if fingerprint([self.run(["ip", "-n", self.ns, "-j", kind, "show"]) for kind in ("addr", "route")]) != ledger["namespace_fingerprint"]:
                return False
            if hashlib.sha256((pathlib.Path(ledger["resolver"]) / "resolv.conf").read_bytes()).hexdigest() != ledger["resolver_sha256"]:
                return False
            return True
        except (CaseError, OSError, KeyError, ValueError):
            return False

    def invalidate_source(self, ledger):
        ledger["source_proof"] = {"verified": False, "reason": "scope_drift"}
        atomic(self.path, ledger)

    def prove(self, ledger):
        from .collector import CaptureDiagnostics, capture_socket, receive, verify_source
        broker = self.spec["brokers"][0]
        host = capture_socket(ledger["interface"])
        child = subprocess.Popen(["ip", "netns", "exec", self.ns, "python3", "-m", "cross_az.collector", "--probe-interface", "eth0", "--duration", "4"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        probe = None
        try:
            if json.loads(child.stdout.readline()).get("event") != "capture_ready":
                return {"verified": False, "reason": "capture_unavailable"}
            code = "import socket,sys;s=socket.socket();s.settimeout(2);s.connect((sys.argv[1],int(sys.argv[2])))"
            probe = subprocess.Popen(["ip", "netns", "exec", self.ns, "python3", "-c", code, broker["ip"], str(broker["port"])], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            packets, deadline = [], time.monotonic() + 4
            diagnostics = CaptureDiagnostics()
            while time.monotonic() < deadline:
                try:
                    packet = receive(host)
                    if packet and packet["syn"]:
                        if len(packets) < 2048:
                            packets.append(packet)
                        else:
                            diagnostics.overflows += 1
                except socket.timeout:
                    pass
                except ValueError as error:
                    diagnostics.error(error)
            output, _ = child.communicate(timeout=2)
            captured = json.loads(output)
            diagnostics.kernel_packets, diagnostics.kernel_drops = struct.unpack("II", host.getsockopt(263, 6, 8))
            capture = {"host": diagnostics.frame(), "namespace": captured.get("quality", {"complete": False, "error_codes": {"quality_missing": 1}})}
            if not captured.get("complete") or not all(q.get("complete") for q in capture.values()):
                return {"verified": False, "reason": "capture_incomplete", "capture": capture}
            namespace = captured["syns"]
            proof = verify_source(namespace, packets, ledger["source_ip"], (broker["ip"], broker["port"]))
            proof["capture"] = capture
            return proof
        except (OSError, ValueError, subprocess.TimeoutExpired):
            return {"verified": False, "reason": "source_unverified"}
        finally:
            host.close()
            for process in (child, probe):
                if process and process.poll() is None:
                    process.kill()
                    process.wait()

    def _rollback(self, ledger):
        remaining = []
        for command in reversed(ledger["undo"]):
            try:
                self.run(command)
            except CaseError:
                remaining.append(command)
        ledger["undo"] = list(reversed(remaining))
        resolver = pathlib.Path(ledger.get("resolver", "/nonexistent"))
        if resolver == pathlib.Path("/etc/netns") / self.ns and resolver.exists():
            try:
                if not (resolver / "resolv.conf").exists():
                    resolver.rmdir()
                elif hashlib.sha256((resolver / "resolv.conf").read_bytes()).hexdigest() == ledger["resolver_sha256"]:
                    (resolver / "resolv.conf").unlink()
                    resolver.rmdir()
                else:
                    remaining.append(["resolver_cleanup_required"])
            except OSError:
                remaining.append(["resolver_cleanup_required"])
        ledger["state"] = "cleanup_incomplete" if remaining else "cleaned"
        atomic(self.path, ledger)
        if not remaining:
            self.path.unlink()
        return ledger

    def cleanup(self):
        with self.lock():
            ledger = self.read()
            if not self.intact(ledger, locked=True):
                raise CaseError("Scope drift or ownership loss; automatic cleanup refused")
            pids = self.run(["ip", "netns", "pids", self.ns]).strip()
            if pids:
                raise CaseError("Scope has active processes; stop and confirm owned tasks first")
            for path in (self.root.parent).glob("*/descriptor.json"):
                descriptor = json.loads(path.read_text())
                if descriptor.get("scope_id") == self.spec["scope_id"]:
                    state = json.loads((path.parent / "state.json").read_text())
                    if state.get("state") not in ("stopped", "failed") or not state.get("stop_confirmed"):
                        raise CaseError("Scope has an active or unconfirmed task")
            return self._rollback(ledger)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("prepare", "cleanup", "inspect"))
    parser.add_argument("--spec-json", required=True)
    args = parser.parse_args()
    try:
        scope = Scope(json.loads(args.spec_json))
        result = scope.prepare() if args.operation == "prepare" else scope.cleanup() if args.operation == "cleanup" else scope.read()
        print(json.dumps({"schema_version": 1, "event": "scope", "result": result}), flush=True)
        if (args.operation == "prepare" and not result.get("source_proof", {}).get("verified")) or result.get("state") == "cleanup_incomplete":
            raise SystemExit(2)
    except (CaseError, OSError, KeyError, ValueError):
        print(json.dumps({"schema_version": 1, "event": "scope", "state": "failed", "error": "Scope preparation or verification failed; inspect dependencies and ownership"}), flush=True)
        sys.exit(2)


if __name__ == "__main__":
    main()
