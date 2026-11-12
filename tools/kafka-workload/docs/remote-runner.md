# Run a workload on an existing cloud client

Use this optional AWS SSM path when Kafka is reachable from a cloud Linux host rather than your local machine. For local use, start with the [workload guide](../README.md); for CIDR verification, use the [cross-AZ guide](../../../byoc-examples/clients/cross-az-verification/). Run the commands below from `tools/kafka-workload`.

## Control an existing remote Linux client

The local controller requires Python 3.9+ and AWS CLI v2 with an authorized local profile. This implementation uses SSM Run Command, not SSH or a Kafka tunnel. The target must be SSM Online, authorized for the selected commands, and privately connected to Kafka. The target needs Python 3.9+, Java 17+, Bash and AWS CLI for artifact installation. Generic workloads do not require AZ discovery, root or capture permissions. Additional capture permissions belong to the cross-AZ case.

Copy [runner.json](examples/runner.json) to a private local working directory and replace its fake region/profile/instance ID. `remote_root` is a private remote installation/state directory. Kafka properties remain on the remote host at an absolute path; the runner JSON contains no Kafka secrets.

Build an immutable runtime bundle locally, then explicitly stage it to a **private** S3 prefix your remote role can read:

```sh
mvn -B verify
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
