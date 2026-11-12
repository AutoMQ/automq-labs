# Kafka workload

Run an explicit topic operation, producer or consumer with the Java Kafka SDK. These commands work independently of AutoMQ AZ routing, AWS and packet capture. The optional runner controls an existing Linux host through AWS SSM; Kafka traffic originates on that host.

For a manual CIDR before/after comparison, use the [cross-AZ case](../../byoc-examples/clients/cross-az-verification/). A laptop or several local containers do not establish real AZ placement.

## Build and run locally

Install Java 17+ and Maven. From this directory:

```sh
mvn -B verify
./workload --help
```

The packaged artifact is `target/workload.jar`; the launcher resolves it relative to its own path and works from any directory. `JAVA_HOME` selects Java; `WORKLOAD_JAR` can select another readable fat JAR. Docker is optional and is not required for these checks.

Copy [client.properties](docs/examples/client.properties) to a private file on the **execution host**, fill in its bootstrap servers and standard Kafka TLS/SASL properties, and restrict it to mode `0600`. The module reads credentials from this file without printing its contents. It does not create network access, upload credentials or configure AZ routing.

Every command in this section executes on the machine running `workload`. Replace the absolute configuration path, topic and run ID before running:

```sh
./workload topic create --config /absolute/private/client.properties \
  --topic dedicated-demo --partitions 9
./workload topic describe --config /absolute/private/client.properties \
  --topic dedicated-demo
```

`create` creates a missing topic and verifies the actual partition count. An existing topic is verified; a partition mismatch fails without resizing it. `describe` does not create it. Use a dedicated test topic; these commands never delete a topic.

In one terminal, start a consumer with a new group and wait for `event: ready` with `start_offsets` for every partition:

```sh
./workload consume --config /absolute/private/client.properties \
  --topic dedicated-demo --run-id demo-unique \
  --group demo-unique-reader --start-position current-end
```

In another terminal, start the producer after the consumer is ready:

```sh
./workload produce --config /absolute/private/client.properties \
  --topic dedicated-demo --run-id demo-unique \
  --rate-mibps 0.0095367431640625 --record-bytes 1024 \
  --compression none --partition-mode round-robin \
  --max-messages 600 --duration-seconds 90
```

This example targets 10,000 uncompressed payload bytes/s (10 KB/s), with at most 600 messages and 90 seconds. The first stop condition ends production. The generic producer default is 1 MiB/s when `--rate-mibps` is omitted. Supported compression values are `none`, `gzip`, `snappy`, `lz4` and `zstd`; partition mode is `round-robin`.

`current-end` snapshots each partition's end before readiness. It reads new records without replaying earlier backlog. `beginning` reads from the beginning; `committed` requires existing committed offsets. Existing group offsets are not silently reset, and this workload does not commit them. Give each full-stream reader its own group. With multiple producers, start **all** readers before any producer; each reader must keep up with their combined output. Use the same run ID for records belonging to one run.

## Read progress and finish a run

Stdout is versioned JSONL. Producer `messages` and `payload_bytes` count acknowledged writes; `max_acked_offsets` are inclusive. Consumer counts matching `workload-run-id` records; `actual_read_*` and `foreign_*` expose other data read. `next_offsets` are exclusive. Payload bytes are uncompressed record values, not network or billing bytes.

Stop the producer first and inspect its `final` event. For each partition, the consumer must reach at least the largest successfully acknowledged producer offset plus one. Keep consumers running until that boundary is reached, then stop them with Ctrl+C. A consumer without a message/duration limit waits for data; it does not infer that a producer is finished. Do not accept errors, unconfirmed writes or an empty run as a completed experiment.

Both roles support `--duration-seconds`, `--max-messages` and `--max-errors` when a bounded standalone run is needed. Limits are per process. Do not give a reader the per-producer message limit when it must read several producers' combined output. Ctrl+C requests bounded SDK shutdown and emits a final event. Exit codes are `0` stopped/verified, `2` arguments/runtime, `3` SDK/configuration/ACK failure, and `4` unconfirmed sends.

## Control an existing remote Linux client

The local controller requires Python 3.9+ and AWS CLI v2 with an authorized local profile. This implementation uses SSM Run Command, not SSH or a Kafka tunnel. The target must be SSM Online, authorized for the selected commands, and privately connected to Kafka. The target needs Python 3.9+, Java 17+, Bash and AWS CLI for artifact installation. Generic workloads do not require AZ discovery, root or capture permissions. Additional capture permissions belong to the cross-AZ case.

Copy [runner.json](docs/examples/runner.json) to a private local working directory and replace its fake region/profile/instance ID. `remote_root` is a private remote installation/state directory. Kafka properties remain on the remote host at an absolute path; the runner JSON contains no Kafka secrets.

Build an immutable runtime bundle locally, then explicitly stage it to a **private** S3 prefix your remote role can read:

```sh
python3 -m runner.bundle --out /absolute/private/runtime.tar
# Record sha256 from the bundle command's JSON output.
aws --profile demo-profile s3 cp /absolute/private/runtime.tar \
  s3://YOUR_PRIVATE_BUCKET/YOUR_DEDICATED_PREFIX/runtime.tar
./run-remote --runner /absolute/private/runner.json install \
  --artifact-s3 s3://YOUR_PRIVATE_BUCKET/YOUR_DEDICATED_PREFIX/runtime.tar \
  --sha256 REPLACE_WITH_BUNDLE_SHA256
./run-remote --runner /absolute/private/runner.json check \
  --config /opt/demo/client.properties
```

The bundle contains the launcher, fat JAR and runner Python source, with per-file hashes. It excludes configuration, examples, credentials and payloads. `install` downloads only the specified S3 object, verifies SHA256, writes a private release and atomically switches `current`. It does not install missing Java/Linux packages, upload properties, create a bucket or grant IAM. Provision dependencies explicitly through your approved host-management process, then repeat `check`.

Each local command starts one remote role and attaches to its progress by default:

```sh
./run-remote --runner /absolute/private/runner.json \
  --state-dir /absolute/private/controller-state start \
  --task-id demo-unique-produce --role produce --run-id demo-unique -- \
  produce --config /opt/demo/client.properties --topic dedicated-demo \
  --run-id demo-unique --rate-mibps 0.0095367431640625 \
  --record-bytes 1024 --max-messages 600 --duration-seconds 90
```

Use the same form with `--role topic` and `-- topic create ...`, or `--role consume` and `-- consume ...`. Topic setup is separate; starting a producer never creates a topic. Add `--detach` only when intentionally leaving attach; a detached task loses its lease unless an owner attaches again.

Keep the private `--state-dir`: it stores the task/controller identity required for recovery. A repeated identical task descriptor returns the same task; a different descriptor with the same task ID fails. A completed role needs a new task ID for another run.

```sh
./run-remote --runner /absolute/private/runner.json \
  --state-dir /absolute/private/controller-state status --task-id demo-unique-produce
./run-remote --runner /absolute/private/runner.json \
  --state-dir /absolute/private/controller-state attach --task-id demo-unique-produce
./run-remote --runner /absolute/private/runner.json \
  --state-dir /absolute/private/controller-state stop --task-id demo-unique-produce
```

SSM returns short snapshots, normally polled about every three seconds; API delay can increase this. Inspect task identity, actual host, frame age and application exit status. Repeated old frames do not become fresh. Ctrl+C sends a separate stop request and confirms the corresponding remote task. `Stop unconfirmed` means retain the identity and retry `status`/`stop` after connectivity returns. Closing a terminal or canceling an SSM request alone does not confirm that the remote process stopped.

The lease is at most 90 seconds and the total lifetime at most 900 seconds. Expiry sends TERM, followed by KILL after a bounded grace period if needed. Each role owns its own lease; stopping one does not stop another. The runner verifies process identity rather than killing every Java process.

## Verify without cloud resources

From any directory, run the absolute path to this checkout's check entry:

```sh
/path/to/automq-labs/tools/kafka-workload/check
# Only Python contracts, using the selected interpreter:
python3 /path/to/automq-labs/tools/kafka-workload/check --python-only
```

The default command runs Maven verification, packaged launcher help, Python unit tests/compilation, runner/case help, and local `prepare` generation with shell syntax, permissions and argument checks. `MVN` can select a Maven executable. It needs no AWS identity, broker, Docker daemon or billable resources. CI runs Java 17 and Python 3.9/3.14 checks on the workload, runner, case and workflow paths.

Real SSM/Kafka/network evidence requires a separately authorized environment. Use the opt-in [AWS E2E runbook](../../byoc-examples/clients/cross-az-verification/docs/aws-e2e.md); CI does not deploy it. Review [stopping and cleanup](../../byoc-examples/clients/cross-az-verification/docs/operations.md) before removing any resources.
