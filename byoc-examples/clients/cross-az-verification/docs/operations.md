# Stop, recover and clean up a run

Keep the case JSON, runner JSON and private generated state until every task has a confirmed terminal state. Each producer, consumer and watch is independently controlled. Stopping a watch does not stop traffic; stopping a producer does not stop its readers. None of these actions deletes a topic or changes CIDR routing.

## Recover a demo round

Use `demo status --config /absolute/private/case.json --state-dir /absolute/private/demo-state` to inspect the latest session without renewing leases. Use `demo stop` with the same options to record stop intent, stop all registered mutable tasks and, once every stop is confirmed, clean that session's precise owned scopes. Neither command follows edited runner targets; it uses the frozen private snapshot.

Status defaults to a short final summary: round state, successful message counts, historical cross-AZ/unknown traffic and cleanup confirmation. Add `--lang zh` for Chinese or `--details` for capture quality, complete network fields and technical phase/task fields. These display options do not change the session, baseline, input fingerprint or runtime. Normal stopped status shows historical evidence, not live traffic. A failed or cancelled round shows its partial counts without claiming a successful baseline. Recovery-required output always includes the original target/task/controller identities and absolute recovery commands, even without `--details`.

`Recovery required` blocks another before/after, including a Preparing phase with no tasks. A dead owner releases its OS lock but leaves its claim for explicit stop recovery. Lost start acknowledgements and temporary missing/Unknown snapshots remain unconfirmed: retain identities and retry status/stop. Do not delete state or use `pkill`. Stop does not wait on the phase-owner lock; a running owner sees stop intent before submitting further business/topic/prepare work. Exact scope-cleanup maintenance is allowed after all earlier mutable jobs have confirmed stops and is deduplicated by saved identity. Cleanup failure retains the session for inspection rather than bypassing scope ownership checks.

If cleanup reached a confirmed failed terminal state, repair its documented host/ownership prerequisite and explicitly invoke `demo stop` again. That invocation may submit one new cleanup attempt per scope, with a new task/controller identity; the old descriptor and result remain in history. Concurrent stop calls compare the same failed attempt under the metadata lock and share the replacement. An active, unknown, lost-ack or stop-unconfirmed attempt is queried/stopped under its original identity and cannot be replaced. Normal failure handling does not loop through cleanup retries. Missing or partially removed ledger objects do not prove successful cleanup: retain `Recovery required` and inspect exact ownership if the helper cannot verify the ledger.

The owner has a 900-second execution budget; stop/cleanup uses a separate 180-second budget. Network loss can prevent confirmation within that budget. A nonzero exit then provides absolute recovery commands and each target/task/controller identity; the remote lease and maximum runtime still bound the remote task independently. Private state and historical windows remain on disk. Topics, groups, CIDR settings and other sessions remain under their existing ownership.

The default prints one running message and the final short summary. Successful before and its status directly show the candidate `automq.zone.cidr.blocks` value and a manual-save/verify next step. Partial candidates are labelled as covering only this round's clients; verify the complete mapping and preserve other sources before changing configuration. Failed or stop-unconfirmed results prioritize recovery. Add `--details` for live/stage progress, peers, exact bytes, capture quality, original times and technical state. After preserves the short historical comparison and any not-comparable warning without repeating the configuration block. This affects presentation only. Unconfirmed recovery always includes exact task/controller/target identities and recovery commands.

## Stop one role or recover a lost terminal

Ctrl+C in an attached local terminal requests a separate remote stop and waits for confirmation. If connectivity is lost, retain task/controller identity and treat the task as unconfirmed until queried. For a generated case role, use the same case, state directory, cohort, client, phase and role:

```sh
./az-case status --config /absolute/private/case.json \
  --state-dir /absolute/private/generated/state --cohort client-a \
  --client client-a --phase before --role produce
./az-case stop --config /absolute/private/case.json \
  --state-dir /absolute/private/generated/state --cohort client-a \
  --client client-a --phase before --role produce
```

Run these from the case directory. Use the exact original cohort, such as `client-a,client-b,client-c`; do not change membership during recovery. Retry the same identity when `stop_confirmed` is false. Never substitute `pkill java`, reuse an unrelated task ID or delete state to force a new start. The generic runner also provides `status`, `attach` and `stop` using its original private `--state-dir` and `--task-id`.

A stopped task is different from a successful experiment. Read both OS/application exit status and final success/error/unconfirmed counters. A lost controller stops renewing only its own task. Lease expiry is bounded to at most 90 seconds; total lifetime is at most 900 seconds, followed by TERM and bounded KILL escalation. A reconnected status query does not automatically start another process. Detached execution still needs owner attach renewal to continue.

## Diagnose a blocked step

| Symptom | Next step |
| --- | --- |
| SSM target unavailable or access denied | Check selected local profile, region, allowed target and SSM Online state. Prepare approved permissions separately. |
| Kafka config unreadable or private endpoint unreachable | Check the absolute path and file mode on the remote host, standard TLS/SASL settings, VPC routing and approved network rules. |
| Wrong actual AZ/private IP or `source_unverified` | Correct topology using trusted ENI/AZ data, then explicitly establish and inspect runtime scope/SNAT proof. |
| Namespace, forwarding or capture permission failure | Ask the host owner to provide a remote runner with effective UID 0 and the required `CAP_NET_ADMIN`/`CAP_NET_RAW`, forwarding/routing and an unused /24 scope. Do not flush global chains or silently enable forwarding. |
| DAD failure or timeout during scope preparation | Inspect the namespace address/DAD state and the recorded rollback result. Preparation must fail and roll back owned objects; do not disable IPv6 or modify global sysctls to pass the check. |
| Source-proof parse errors, drops or overflow | Inspect the separate host/namespace parse-code, kernel-drop and overflow counters. IPv6 TCP, unknown/over-budget extensions and truncation degrade quality; only confirmed normal non-TCP ICMPv6/MLD control traffic is excluded. Diagnostics contain header classifications, not payloads. |
| Consumer barrier missing | Start each selected consumer and wait for current-end readiness for every partition; do not bypass the barrier. |
| Stale frame or transport disconnect | Check frame sample time/age, keep identities and query status. No current zero-byte conclusion is available. |
| Unknown peers or capture drops | Repair physical IP/AZ inventory or capture coverage; preserve the unknown/drop counters as a verification gap. |
| Baseline lacks cross-AZ bytes | Record the lack of distinction and verify physical leaders/source/coverage. Do not fabricate a baseline. |
| `Not comparable` | Read the listed workload/window/quality/offset differences; keep the raw evidence and repeat with a new run ID if necessary. |

## Optional manual controls

To inspect traffic response, stop one producer while keeping its watch attached. Other roles continue under their own controllers. A completed role cannot be silently restarted within the same phase; use a new experiment/run ID for another repeat. This observation is separate from the default two-round comparison.

For a manual unmatched/wrong-CIDR experiment, first record the original value, scope and whether it is explicitly set, obtain an appropriate controlled configuration window, and define the expected routing difference. Change only the selected configuration yourself. Keep topic, positions, record size, compression, rate, partition coverage and cohort comparable; rebuild clients/windows. A detected routing regression is an experimental observation, not necessarily a tool failure.

A separate `client.id` priority experiment may test `automq_az` over CIDR and consumer `client.rack`. The primary case rejects these overrides. Use an explicitly separate configuration and the generic workload or a separately designed observation run; do not weaken the main-case checks to obtain a pass. Keep physical source/AZ evidence unchanged. Do not use the label as proof of a client's location.

Restore configuration manually only after checking the original scope/value/presence and any concurrent edits. Do not overwrite another operator's new value. Removing an explicitly set value is not always equivalent to setting an empty value or restoring a runtime matcher. Verify both the intended effective configuration and new-client network paths for the target version; do not infer runtime recovery from configuration readback alone.

## Clean up only owned resources

Stop and confirm every producer, consumer and watch before removing its scope. Run the generated `CLIENT/PHASE/runtime-cleanup.sh` explicitly. It removes only its recorded namespace/veth/SNAT/forwarding objects and refuses active owned tasks. A cleanup failure needs ownership/identity inspection, not a broad firewall flush.

A scope left by an earlier failed preparation may report address drift. Confirm its roles are stopped, then verify the exact namespace, interfaces and rules against the owned ledger before explicit cleanup. Retain the ledger and inspect any refused cleanup; do not edit fingerprints or skip ownership/source gates to resume a failed scope. A normal DAD tentative-to-stable transition is handled by waiting before the initial fingerprint is fixed, not by disabling IPv6.

Keep a resource ledger with created/existing status, IDs, run ID, owner and cleanup outcome. Remove only objects confirmed as newly created for this run: dedicated artifact objects/prefixes, test topics when explicitly owned and no longer needed, and separately authorized temporary clients/IAM/network objects. Existing topics/groups and cluster configuration remain under their owners' control. There is no unconditional topic/group deletion or infrastructure destroy command in this case. Retain the small statistical evidence needed for review, then securely remove local/remote private state according to your policy.
