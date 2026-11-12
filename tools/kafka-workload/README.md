# Send and consume Kafka test data

Create a dedicated topic, send a bounded workload and read it with the Java Kafka client. Run these commands on any machine that can reach your Kafka cluster. No AWS or AZ configuration is needed for local use.

For a before/after CIDR routing demonstration controlled from your laptop, use the illustrated [cross-AZ guide](../../byoc-examples/clients/cross-az-verification/).

## 1. Build and prepare a connection file

Install Java 17+ and Maven. From `tools/kafka-workload`:

```sh
mvn -B verify
./workload --help
```

Copy [client.properties](docs/examples/client.properties) to a private file, set its bootstrap servers and required Kafka TLS/SASL settings, then restrict access:

```sh
chmod 600 /absolute/private/client.properties
```

The properties file belongs on the machine running the workload. Keep credentials in that file rather than command arguments. All commands below use placeholders you must replace with your connection path and a unique run/group ID.

## 2. Prepare a test topic

```sh
./workload topic create --config /absolute/private/client.properties \
  --topic dedicated-demo --partitions 9
```

An existing topic is checked for the requested partition count; it is not resized or deleted. Use `topic describe` with the same options except `--partitions` to inspect it.

## 3. Start the consumer first

In one terminal, wait for the `ready` event before starting the producer:

```sh
./workload consume --config /absolute/private/client.properties \
  --topic dedicated-demo --run-id demo-unique \
  --group demo-unique-reader --start-position current-end \
  --max-messages 600 --duration-seconds 120
```

This single-producer example reads up to 600 matching messages and waits at most 120 seconds. `current-end` starts with new records; it does not replay earlier backlog.

## 4. Send a small workload

In a second terminal:

```sh
./workload produce --config /absolute/private/client.properties \
  --topic dedicated-demo --run-id demo-unique \
  --rate-mibps 0.0095367431640625 --record-bytes 1024 \
  --compression none --partition-mode round-robin \
  --max-messages 600 --duration-seconds 90
```

The producer targets **10 KB/s** (10,000 payload B/s), at most 600 messages or 90 seconds, whichever comes first. Use the same run ID in both terminals. Both commands stop at their configured limits; Ctrl+C can stop them early.

## 5. Check the final results

Output is JSON lines with ready, progress and final events. In the successful single-producer example, expect 600 acknowledged producer messages and 600 matching consumed messages, with no errors or unconfirmed writes. If production stops early or fails, inspect the actual counts rather than assuming the limit was reached.

Payload bytes measure record values, not network or billing traffic. The workload does not commit consumer offsets. For multiple producers/readers or exact completion checks, see the [options and result reference](docs/reference.md).

## Run on a cloud client

Use the optional [SSM runner guide](docs/remote-runner.md) to install a checksum-verified runtime and control an existing Linux client. Kafka traffic then originates from that client; the runner does not create infrastructure or a Kafka tunnel.

For real client AZ placement, packet capture, CIDR values and the paired demonstration, use [cross-AZ verification](../../byoc-examples/clients/cross-az-verification/).

## Verify without cloud resources

From the repository root:

```sh
./tools/kafka-workload/check
# Skip Java build and run only Python contracts:
python3 ./tools/kafka-workload/check --python-only
```

These checks need no broker, AWS identity, Docker daemon or cloud deployment. The [opt-in AWS runbook](../../byoc-examples/clients/cross-az-verification/docs/aws-e2e.md) covers separately authorized real-environment verification.
