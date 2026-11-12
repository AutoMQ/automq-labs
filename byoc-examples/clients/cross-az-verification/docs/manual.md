# Run producer, consumer and capture separately

Use this optional path when you need individual role controls. For the normal one-command round, use the [main guide](../README.md). Complete [first-time setup](setup.md) first. Commands in this document run from the case directory unless an absolute path is shown.

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

Use [operations and recovery](operations.md) for stopping, optional manual scenarios and cleanup, and the [opt-in AWS E2E runbook](aws-e2e.md) for real-environment verification. The repository's [cloud-free check](../../../../tools/kafka-workload/#verify-without-cloud-resources) does not create paid resources.
