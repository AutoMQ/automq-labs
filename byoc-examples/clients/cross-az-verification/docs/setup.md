# First-time setup

Complete this preparation before following the [comparison guide](../README.md). Commands run locally unless marked **on each cloud client**. The example assumes existing clients and a private S3 bucket; it does not deploy infrastructure.

## 1. Check the environment

| Where | Required preparation |
| --- | --- |
| Local machine | Python 3.9+, AWS CLI v2 and an authorized AWS profile; Java 17+ and Maven to build the runtime |
| Each cloud client | Linux, SSM Online, Python 3.9+, Java 17+, Bash, AWS CLI, `ip` and `iptables`; private Kafka connectivity |
| Capture privileges | The remote SSM runner executes as root, with `CAP_NET_ADMIN` and `CAP_NET_RAW`; host forwarding/routing already permits the capture network |
| AWS access | Local permission to run/read SSM commands on the selected clients; each target's instance role can read the dedicated private S3 artifact prefix |
| AutoMQ | CIDR routing supported for the target product/WAL/network configuration; trusted physical broker IP/port/AZ/rack data |

Have the host owner prepare missing tools, permissions and forwarding through your approved process. This example does not install packages, grant IAM, change global forwarding or open SSH. The local machine does not need a direct route to private Kafka.

**On each cloud client**, create a mode-`0600` Kafka properties file at an absolute path, such as `/opt/demo/client.properties`. Include its bootstrap servers and required Kafka TLS/SASL settings. Keep credentials there; case/runner JSON and the runtime archive must not contain them. Do not add an `automq_az` client ID override or consumer `client.rack` for this case.

## 2. Prepare private case and runner files

From the repository root:

```sh
repo_dir="$(pwd)"
case_dir="$repo_dir/byoc-examples/clients/cross-az-verification"
workload_dir="$repo_dir/tools/kafka-workload"
private_dir=/absolute/private/automq-demo
mkdir -p "$private_dir"
chmod 700 "$private_dir"
cp "$case_dir/examples/case.json" "$private_dir/case.json"
cp "$case_dir/examples/runner-a.json" "$private_dir/runner-a.json"
```

For three real clients, copy `examples/case-three-az.json` as `case.json`, plus `runner-a.json`, `runner-b.json` and `runner-c.json` into the same private directory. Every selected client must be prepared and installed separately.

Edit the placeholders using trusted inventory:

| File / field | What to enter |
| --- | --- |
| Runner `region`, `profile`, `instance_id` | The authorized local AWS profile and actual client target |
| Runner `remote_root` | A private remote installation/state directory, such as `/opt/automq-labs/client-case` |
| Case `run_id`, `topic` | A unique experiment ID and a dedicated test topic; retain the values for the paired rounds |
| Case `clients.*.runner_file` | The matching local runner JSON, relative to the case file or absolute |
| `remote_connection_file` | The properties file's absolute path **on that cloud client** |
| `zone_id`, `source_ip`, `source_cidrs` | Actual AZ ID, client ENI/source IPv4 and CIDR prefixes presented to the brokers |
| `scope_cidr` | An unused IPv4 /24 pool for capture isolation, disjoint from host, VPC and broker routes |
| `brokers` | Physical broker IPv4, port, AZ ID and rack; each tested AZ needs a same-AZ broker |

The supplied addresses, AZs and target IDs are placeholders. AZ labels and localized Kafka metadata alone do not prove placement or original leaders. Unknown NAT/SNAT or incomplete inventory must be resolved before making a locality claim. Valid nested source prefixes use longest-prefix matching; identical prefixes assigned to different AZs are rejected.

Keep the sample workload at 10 KB/s, 1024 B per message, at most 600 messages/90 seconds unless you intentionally choose another budget. Limits apply per producer; each independent consumer reads the entire selected cohort's output.

You can validate and generate local inspection material without contacting AWS:

```sh
"$case_dir/az-case" prepare --config "$private_dir/case.json" \
  --out "$private_dir/generated"
```

Use a new empty output directory. This produces candidate topology, `zone-cidr.txt` and optional manual scripts; it does not install or start anything. A `source_unverified` candidate needs the runtime source check that `demo before` performs after installation.

## 3. Build and bundle the runtime

```sh
cd "$workload_dir"
mvn -B verify
python3 -m runner.bundle --out "$private_dir/runtime.tar" --case-dir "$case_dir"
```

Record the `sha256` from the bundle's JSON output. This archive contains the workload JAR, launcher and runner/case code. It excludes examples, properties, credentials and generated state.

## 4. Upload to your approved private artifact prefix

Set values for an **existing** private bucket/prefix and the local profile authorized to upload there:

```sh
artifact_profile=YOUR_LOCAL_AWS_PROFILE
artifact_s3=s3://YOUR_PRIVATE_BUCKET/YOUR_DEDICATED_PREFIX/runtime.tar
bundle_sha256=REPLACE_WITH_BUNDLE_SHA256
aws --profile "$artifact_profile" s3 cp "$private_dir/runtime.tar" "$artifact_s3"
```

Each selected client's instance role must already have read access to that object. Keep it private. These commands do not create a bucket or grant permissions.

## 5. Install and check every selected client

```sh
"$workload_dir/run-remote" --runner "$private_dir/runner-a.json" install \
  --artifact-s3 "$artifact_s3" --sha256 "$bundle_sha256"
"$workload_dir/run-remote" --runner "$private_dir/runner-a.json" check \
  --config /opt/demo/client.properties
```

Replace the check's remote properties path with the one in your case. For a three-client case, repeat both commands with `runner-b.json` and `runner-c.json`, using each client's corresponding properties path.

Installation downloads the specified object, verifies the SHA256 and activates a private release. Check verifies the target and its basic workload prerequisites; it does not prove the capture source. The case's before step additionally verifies actual AZ/IP, capture permissions and the isolated source path before sending data. A failed prerequisite blocks the round; use [troubleshooting](operations.md) rather than bypassing it.

Return to the repository root, then follow [Run the comparison](../README.md#run-the-comparison) with your case path and a private state directory:

```sh
cd "$repo_dir"
```

Keep both paths unchanged for after. Preparing another case or deleting state does not recover an unconfirmed earlier run.

## Advanced details

[Independent role controls](manual.md) explain the manual three-terminal path and per-partition completion. [Operations and recovery](operations.md) covers privilege/capture failures, bounded task lifetimes, exact ownership cleanup and restoring configuration. The [AWS runbook](aws-e2e.md) describes complete multi-AZ validation.
