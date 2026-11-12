# Opt-in AWS end-to-end verification

This is the independent entry for real SSM, Kafka and packet-path verification. It is a manual runbook, not a CI deployment job. Run it only against explicitly authorized clients, Kafka resources and configuration scopes with a defined load budget. The cloud-free check does not prove any AWS route or product locality result.

## Establish the external prerequisites

Record the target account/region, permitted existing client instance IDs, real AZ IDs/ENI addresses, physical broker addresses/racks and target product version/WAL/network support in a private ledger. One client verifies only its own AZ. A full three-AZ result requires both before and after rounds on three real clients; a single-AZ comparison plus a three-client after round is incomplete.

Provide approved SSM access, private Kafka routing, restricted remote properties and the documented Java/Python/network tools. Obtain the host owner's explicit approval for isolated network scope preparation and confirm IPv4 forwarding is already configured. Prepare a private artifact prefix and remote read access separately. New machines, IAM, security rules and billable resources are external preparations; no case command creates them.

Choose a unique dedicated topic/run ID, record which resources already existed, and define per-producer payload rate/message/duration limits. The public example is 10 KB/s per producer, 600 messages and no more than 90 seconds. Start consumers first and allow enough drain time; their aggregate input is the sum of all selected producers. Avoid unrelated writers on the topic.

Agree on the original/effective configuration scope and a controlled manual baseline/change/restoration plan. Do not silently clear an existing mapping or override another operator's concurrent edits. The main case must have no `automq_az`/`client.rack` overrides. Establish original physical leader distribution from an independent trustworthy source when testing causality.

## Verify the single-command round

After independently verifying prerequisites and the installed runtime manifest, invoke `demo before --config /absolute/private/case.json --clients client-a --state-dir /absolute/private/demo-state` from one local terminal. Verify check/topic/source proof, all watches before consumers and all consumers current-end ready before any producer, live raw L3 counters/age/quality, successful producer finals, every consumer at cohort ACK+1, retained business sample times, all registered tasks stop-confirmed and precise scope cleanup. Inspect the private session journal; topic/groups must remain. Do not substitute unit tests for this authorized remote smoke.

Manually configure CIDR and invoke `demo after` separately when that scenario is authorized. Test missing baseline, changed input/target, duplicate after, stop recovery and an empty Preparing owner with local fixtures before live failure injection. Local launcher/API changes do not require reinstalling unchanged remote execution modules; compare the installed manifest before deciding. A one-client auto-before smoke does not complete three-AZ after verification, restoration or final EC2/IAM/network cleanup.

## Execute the documented manual sequence

Follow the [case README](../README.md) without combining its explicit steps into an automatic A/B script:

1. Build and explicitly install the checksum-verified secret-free runtime; keep properties remote and private.
2. Prepare local materials, inspect `source_unverified` candidates, then run every selected client's check and explicit runtime preparation. Verify actual instance/AZ, ENI/SNAT source proof, capture scope, and source-prefix/rack match.
3. Explicitly create/verify the dedicated topic. Establish the approved unmatched baseline yourself.
4. Start all baseline watches and consumers. Confirm every consumer's current-end readiness before starting any producer. Observe actual successful workload, raw Cross-AZ/Unknown bytes and fresh complete windows.
5. Finish/stop producers, verify final ACK boundaries, drain every consumer through the cohort target offsets, save each client's retained valid business window, stop consumers/watches and explicitly clean up unused before scopes.
6. Manually submit and check the intended complete CIDR value. Prepare after scopes and new connections; repeat the same workload/cohort/readiness/drain sequence, preserving direct historical before/after comparison with the original sample times.
7. Stop and confirm every role, perform explicit owned scope cleanup and restore the approved configuration manually when required. Verify new-client runtime routes after restoration, not only visible configuration.

A real run may show residual Cross-AZ traffic or insufficient baseline distinction. Keep those results. No result is made successful by rounding a rate to zero, omitting unknown peers, discarding control traffic or presenting an idle/stale final sample as the business window.

## Retain reviewable evidence

Keep a private record of the exact source revision/runtime SHA256, sanitized inputs, task/controller identities, actual client host/AZ/source proof, topic creation status, original/effective configuration scope and manual changes. Preserve both phases' original window sample times/quality, physical peers, raw TX/RX Same-AZ/Cross-AZ/Unknown bytes, actual producer/consumer successful counters and per-partition offset boundaries. Show fresh LIVE output and historical windows distinctly.

Record at least these outcomes separately: generic workload/runner lifecycle; single-AZ two-round path observation; full three-AZ two-round coverage; and negative/recovery checks. A missing cloud prerequisite or unexecuted scenario remains unverified. Never substitute unit-test success, Terraform formatting or a generated command for a real network result.

With controlled inputs, verify invalid/conflicting CIDRs, new unknown peers, missing capture permission, dropped/incomplete samples, stale/repeated frames, no workload and small nonzero cross-AZ bytes. These can use fixtures without disrupting an environment. For live lifecycle checks, verify Ctrl+C stop, lost-control lease expiry, status/stop recovery by identity, repeated-start protection and role independence within the agreed budget. Do not inject a production IAM/network failure or route mismatch without explicit authorization.

Use [operations and recovery](operations.md) to confirm stops, restore configuration and remove only ledger-owned new resources/artifacts. Record remaining resources, owner and cleanup outcome; do not claim cleanup from a command submission alone. Store statistics/headers only—no full packet payloads, passwords or credential-bearing configuration in the repository.
