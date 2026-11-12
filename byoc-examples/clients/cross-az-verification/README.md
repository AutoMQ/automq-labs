# Observe client cross-AZ traffic before and after CIDR routing

Run one round from one local terminal with `demo before` or `demo after`, or control observation, consumption and production independently with the manual commands. Execution uses real Linux clients in the selected AZs. Observe an unconfigured or unmatched baseline, stop and drain the workload, manually configure `automq.zone.cidr.blocks`, then repeat with new connections and a new window. Kafka traffic and packet capture stay on the remote client.

This case orchestrates one selected round or generates independent manual commands and displays network evidence. It does not create clients, change cluster configuration or automatically chain the two rounds. The [generic workload](../../../tools/kafka-workload/) also works without AZ/CIDR inputs.

## Prepare the execution environment

You need an existing AutoMQ instance whose version, WAL mode and network support the intended multi-AZ routing. Independently verify physical broker IP/port/AZ and rack values, plus the original leader distribution when claiming a before/after routing change. Localized client metadata alone cannot establish original physical leaders.

On the local control machine, install Python 3.9+ and AWS CLI v2, with a profile authorized for SSM Run Command to the selected clients. For local builds, install Java 17+ and Maven. On each remote Linux client, provide Python 3.9+, Java 17+, Bash, AWS CLI, `ip` and `iptables`; the SSM agent must be Online. Provide private Kafka reachability and a mode-`0600` Kafka properties file at the configured **remote absolute path**. Do not include Kafka secrets in case/runner JSON, argv or the runtime bundle.

The case uses an explicitly prepared network namespace, veth and owned SNAT/forwarding rules to isolate its workload from other host traffic. The current implementation requires the remote runner to execute as effective UID 0 (root), with `CAP_NET_ADMIN` and `CAP_NET_RAW` available for scope preparation and capture. Non-root capabilities alone do not satisfy its root-owned ledger and scope checks. IPv4 forwarding must already be enabled by the host owner and the existing firewall/routing must permit the owned scope. It does not change global `net.ipv4.ip_forward`, flush firewall chains or silently install packages. Choose an unused `scope_cidr` /24 pool per client; exclude host, VPC and broker routes. A conflict or missing privilege blocks preparation. Generic workload use does not require this scope.

The IPv4 case preserves IPv6 on the host and namespace. Scope preparation waits within a bounded deadline for IPv6 Duplicate Address Detection (DAD) to finish before recording the namespace address fingerprint. `dadfailed` or a timeout fails preparation and rolls back this run's owned objects; a normal tentative-to-stable transition is not external drift. Do not disable IPv6 or change global sysctls to work around this check.

One real client permits a partial, one-AZ observation. For a complete three-AZ comparison, use a different real client in each AZ. Labels, local containers and tunnel exits do not substitute for placement. Every AZ needs a same-AZ physical broker and verified source evidence.

## Run one round from one terminal

After completing the environment and runtime installation prerequisites below, use the absolute launcher from any local working directory:

```sh
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/demo before \
  --config /absolute/private/case.json --clients client-a --state-dir /absolute/private/demo-state
# Manually configure and verify automq.zone.cidr.blocks between these commands.
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/demo after \
  --config /absolute/private/case.json --state-dir /absolute/private/demo-state
```

Calling a round authorizes checks, topic creation or partition-count verification, owned scope preparation/source proof, workload, capture and precise owned scope cleanup. It retains topics/groups and local history. No separate terminal windows open. The launcher does not install runtime packages, change CIDR, create EC2/IAM/security groups or restore cluster settings.

Before selects all template clients unless `--clients` is supplied. It copies the template into a fresh private session with a new run ID and freezes each selected runner target. After defaults to that baseline cohort and requires the latest successful before, unchanged inputs/targets and no prior after attempt. Each phase has new scope/task/controller/group identities and current-end connections. A new before allocates another session; retain the same template and state directory for its paired after.

The default prints one running message and a short final summary. It shows confirmed messages sent and consumed, cross-AZ send/receive bytes and unknown-peer traffic from the saved historical business window, the result, and stop/cleanup confirmation. It does not scroll sampling frames or peer tables. After shows the before/after window values together and keeps any not-comparable warning. Human-readable units never turn nonzero bytes into zero; the exact bytes remain in saved JSON and details.

The public launcher defaults to English. Add `--lang zh` for Chinese. Use `--details` for stage progress, live sampling, peer IP/AZ, exact directional bytes, quality, original sample times, CIDR candidates, paired commands and technical phase state:

```sh
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/demo status \
  --config /absolute/private/case.json --state-dir /absolute/private/demo-state --lang zh --details
```

Successful before and its default status show a copyable `automq.zone.cidr.blocks=<candidate value>` line. Manually save and verify the complete mapping in the console before running after; `--details` is not required to retrieve it. The full candidate comes from the current original template only when its selected inputs still match the saved fingerprint. If that template is missing or changed, status still works with frozen targets and labels the fallback CIDR as covering only this round's clients. Verify the complete mapping and preserve other sources before editing existing configuration. Failed, cancelled or stop-unconfirmed results do not recommend applying the candidate or running after.

Final/status results use the saved **historical business window**, not the idle window after traffic stops. Existing successful before state needs no rerun or migration. Unknown peers, incomplete capture or missing business progress cannot establish zero cross-AZ traffic. Cross-AZ=0 before means insufficient baseline distinction; after residual bytes and unequal actual window load remain visible. Successful execution confirms lifecycle/evidence completion and does not prove CIDR eliminated cross-AZ traffic. Unconfirmed recovery still prints exact identities and recovery commands without requiring details.

Execution is bounded to 900 seconds overall; setup, readiness, producer and drain waits also have finite budgets. Stop/cleanup has a separate 180-second budget. Ctrl+C or failure requests every registered owned task to stop, then cleans only safe owned scopes. An unconfirmed start/stop or cleanup leaves `Recovery required`, exits nonzero and prints task/controller/target identities and absolute recovery commands. Status does not renew leases; stop can be repeated using the saved targets even if the template or runner files were edited. Keep the private state until recovery is complete:

```sh
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/demo status \
  --config /absolute/private/case.json --state-dir /absolute/private/demo-state
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/demo stop \
  --config /absolute/private/case.json --state-dir /absolute/private/demo-state
```

After repairing a cleanup prerequisite, explicitly call `demo stop` to retry a confirmed stopped/failed cleanup. It creates at most one new maintenance attempt per scope for that invocation and retains the original task/controller/result; concurrent stops share the replacement. Active or unknown attempts keep their original identity. A missing/unverifiable ledger remains `Recovery required` and needs ownership inspection.

The phase-owner lock covers checks even before tasks exist. Another start is rejected while an owner is active or a persisted phase needs recovery. Stop records intent independently of that long lock. A missing response after start does not prove the remote task never started; do not remove state or retry with another identity. The manual per-role commands below remain available and only renew/stop their own role.

## Fill in neutral example inputs

Copy [examples/case.json](examples/case.json) for one client or [examples/case-three-az.json](examples/case-three-az.json) for three clients, together with the referenced `runner-*.json`, into a private local directory. The supplied addresses, AZ names and instance IDs are placeholders. Replace them with independently verified values and choose a unique `run_id`. Keep that ID unchanged between `before` and `after`; a new experiment needs a new ID and output directory.

Case JSON fields are versioned with `schema_version: 1`. `runner_file` is a local path relative to the case file; `remote_connection_file` is an absolute path on its target. `source_ip` is the expected ENI/SNAT source, `source_cidrs` are routing candidates, and `scope_cidr` allocates isolated namespace addresses. Broker `rack` must match its physical `zone_id`. IPv4 is supported. CIDRs must be canonical; identical prefixes assigned to different AZs fail, while nested prefixes use longest-prefix matching.

The example producer target is 10 KB/s = 10,000 B/s = `0.0095367431640625` MiB/s, with 1024-byte records, no compression, at most 600 messages and 90 seconds. In this case, `duration_seconds` and `max_messages` apply only to each producer; they are not passed to consumers. Readers need the entire selected cohort's output. Keep them attached through the drain check, then explicitly stop them. Their runner lease and total lifetime remain bounded; `max_errors`, when supplied, applies to both roles. Three such producers offer approximately 30 KB/s of aggregate payload to **each** independent reader.

From this directory, generate local material only:

```sh
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/az-case prepare --config /absolute/private/case.json \
  --out /absolute/private/generated
# Select a single client from a larger case instead:
# /absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/az-case prepare --config /absolute/private/case.json \
#   --out /absolute/private/generated --clients client-a
```

Output includes `preparation.json`, `cohort.json`, `zone-cidr.txt`, `topic-create.sh`, and `CLIENT/{before,after}/{check,runtime-prepare,watch,consume,produce,runtime-cleanup}.sh`. Shell scripts have mode `0700` and contain local control commands. Prepare does not contact AWS/Kafka, create a topic/namespace, start a process or submit configuration.

For the three-AZ example, the **candidate** complete value is:

```text
example-az1@10.40.1.0/24<>example-az2@10.40.2.0/24<>example-az3@10.40.3.0/24
```

`source_unverified` means this is not ready to paste as proven routing. Host identity and a subnet mapping do not prove the source presented to the broker after NAT/SNAT. Explicit runtime preparation must establish the owned source path, and the operator must check the verified source against the intended CIDR and rack. If needed, `discover-aws --config FILE --profile PROFILE --region REGION` performs explicit read-only discovery of candidate ENIs; it does not prove the runtime path.

## Install the secret-free runtime explicitly

On the local control machine, build from the repository's `tools/kafka-workload` directory:

```sh
mvn -B verify
python3 -m runner.bundle --out /absolute/private/runtime.tar \
  --case-dir /absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification
```

Record the returned SHA256. This adds `cross_az` Python source to the standard launcher/JAR/runner bundle; it excludes examples and configuration. Stage that archive to a private S3 prefix and use the [runner install command](../../../tools/kafka-workload/#control-an-existing-remote-linux-client) for each target, explicitly specifying the S3 URI and SHA256. The target role needs read access to that prefix. Missing IAM or dependencies must be prepared explicitly; `prepare` does not do this work.

The generated commands use the same installed release for scoped workload and collection. Keep local `generated/state` private and retain it for status, stopping and the before/after evidence. Never copy a credential-bearing properties file into a public example or runtime archive.

## Run the baseline manually

First preserve the original cluster configuration, its scope and whether it was explicitly set. Confirm that the selected sources are not currently matched by effective CIDR routing. Existing mappings are not automatically cleared. If establishing a baseline would affect other workloads, use an approved controlled configuration or another source. Main-case checks reject `client.id` containing an `automq_az` override and consumer `client.rack`; those would bypass or change the intended CIDR comparison.

All following commands run **locally** and target the configured remote client. For each selected client, run its generated `before/check.sh`, inspect actual instance/AZ, private IP, dependencies, remote properties and reachability, then explicitly prepare its scope:

```sh
/absolute/private/generated/client-a/before/check.sh
/absolute/private/generated/client-a/before/runtime-prepare.sh
```

A read-only check alone leaves source proof unverified. Verify the `runtime-prepare` result and fix any identity/source/permission conflict before continuing. Explicitly create/verify the topic once:

```sh
/absolute/private/generated/topic-create.sh
```

An existing topic is checked without resizing or deleting it. Topic creation does not prove original leader placement. The generated cohort is fixed for this run: a three-client run requires all three consumers to be ready before **any** producer can start.

For one client, open the following three local terminals in order:

| Terminal | Local command | Remote effect and expected evidence |
| --- | --- | --- |
| 1 | `/absolute/private/generated/client-a/before/watch.sh` | Starts capture for the prepared scope; shows freshness, capture quality and physical peers. Idle output waits for successful workload. |
| 2 | `/absolute/private/generated/client-a/before/consume.sh` | Starts a unique full-partition reader at current end. Wait for its `ready` event and all `start_offsets`. |
| 3 | `/absolute/private/generated/client-a/before/produce.sh` | Starts only this producer after the whole cohort readiness barrier; displays actual acknowledged messages/bytes. |

For three AZs, start every selected `watch.sh`, then every `consume.sh`, wait for every consumer to be ready, and only then start the three `produce.sh` commands. The producer entry refuses a missing readiness barrier instead of starting other roles. Consumers use independent groups and the shared phase run ID, and read all selected producers' new records. No script implicitly starts another role.

## Drain, retain the baseline, and configure CIDRs

Let a full warm observation window carry successful producer **and** consumer progress. If no cross-AZ bytes appear in the baseline, the baseline has no distinction; inspect topology, original partitions and workload instead of claiming an improvement.

1. Let each producer finish within its budget, or Ctrl+C each producer. Confirm the remote terminal state and producer final events, including successful offsets, errors and unconfirmed writes.
2. Keep all consumers and watches attached. For each partition, each consumer's `next_offsets` must reach the maximum cohort producer `max_acked_offsets + 1`. A missing/error final or an incomplete drain cannot establish a comparable round.
3. Stop each consumer after drain. Before stopping watch, preserve the most recent valid **running business window** for each selected client:

```sh
/absolute/path/to/automq-labs/byoc-examples/clients/cross-az-verification/az-case snapshot --config /absolute/private/case.json \
  --state-dir /absolute/private/generated/state --cohort client-a \
  --client client-a --phase before --name baseline
```

The snapshot refuses incomplete cohort final offsets or drain evidence; keep consumers running and retry instead of treating that failure as a completed baseline. For the three-AZ cohort, use `--cohort client-a,client-b,client-c` in all direct commands and snapshot each client. The snapshot retains original sample time/quality and attaches final offset/drain evidence; an idle final window does not replace the valid window. A stale or missing valid retained window fails rather than saving a false zero.

4. Ctrl+C each watch and confirm it stopped. Explicitly remove each now-unused owned before scope with its `before/runtime-cleanup.sh`.
5. Manually set `automq.zone.cidr.blocks` in the intended Console configuration scope, using the verified complete `zone-cidr.txt` value. Check the visible effective value, source-prefix/rack match and concurrent changes. Configuration visibility alone is not runtime routing proof.

## Run the after phase with new connections

Keep the same case, cohort, client positions, topic, partitions, record size/compression, rate and producer limits. Run each selected `after/check.sh` and `after/runtime-prepare.sh`, then repeat the three-terminal sequence with `after/watch.sh`, `after/consume.sh` and `after/produce.sh`. All consumers must be ready before any producer. New phase groups snapshot current end, so the previous phase's backlog is not replayed as new traffic.

The watch view keeps the original `HISTORICAL before` sample and compares it to a valid retained after business window, alongside the current `LIVE` window. Stop producers, drain all consumers, and retain the after watch long enough to see the completed offset evidence. Inspect any `Not comparable` reasons; equal target rates alone do not prove comparable actual load. Then stop consumers/watches and explicitly clean up after scopes.

## Interpret the terminal

The view reports actual host/instance/AZ/source, task ID, role states, successful producer/consumer window counters, physical peer IP/port/AZ, TX/RX raw bytes, L3 B/s, current-window and cumulative `same`, `cross` and `unknown` counts, sample time, frame age and quality. `LIVE` describes the current frame; `HISTORICAL` keeps the original business-window sample time. Successful producer/consumer counters establish that data actually flowed; no workload, a warmup, stale frames, dropped packets, broken scope or unknown peers cannot produce a valid zero conclusion.

Only a full, fresh window with verified scope/source, successful work in both directions, nonzero observed local traffic, and exactly zero raw Cross-AZ **and** Unknown bytes supports: “No cross-AZ TCP traffic observed in this window (client scope, L3 bytes).” Rounded `0.000 B/s` is not evidence of zero bytes. Inspect each AZ/window independently.

The collector counts IPv4 L3 lengths, including TCP headers and retransmissions, at its declared capture point. Those bytes differ from uncompressed Kafka payload and cloud-billed traffic. Unknown/new peers remain visible. Small cross-AZ bytes remain cross-AZ bytes; metadata, coordinator and retry traffic are possible explanations, not an automatic attribution. This observation does not promise that every packet or the cloud bill is always zero. A known-broker-only `iftop` filter can be an auxiliary check, but cannot independently establish complete coverage or Unknown=0.

This case does not support IPv6 Kafka traffic. The parser validates header lengths and walks supported IPv6 extension headers within fixed header-count and byte budgets. Only traffic confirmed as normal non-TCP IPv6 control traffic, such as ICMPv6/MLD, is excluded. IPv6 TCP, unknown extensions, exhausted parsing budgets and truncated paths remain unsupported/parse errors and degrade capture quality. Source-proof diagnostics distinguish host-side and namespace-side parse codes, kernel drops and overflow without storing payloads.

Use [operations and recovery](docs/operations.md) for stopping, optional manual scenarios and cleanup, and the [opt-in AWS E2E runbook](docs/aws-e2e.md) for real-environment verification. The repository's [cloud-free check](../../../tools/kafka-workload/#verify-without-cloud-resources) does not create paid resources.
