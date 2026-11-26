---
last_updated: 2026-11-26
---

# Advanced configuration and troubleshooting

Use the [quick start](./README.md) for the default deployment. This reference
covers custom settings, source preparation, and troubleshooting.

## Permissions and connectivity

The Terraform caller needs permission to read GKE/project metadata, create
namespace/KSA/GSA resources, manage the relevant IAM bindings and firewall
rule, and enable `iamcredentials.googleapis.com`.

The Console's existing Google service account must be able to reach the GKE
API and manage Kubernetes resources. The companion Console setup owns its
`roles/container.admin` binding. Workers use their own GSA through Workload
Identity; this example grants `roles/iam.workloadIdentityUser` for the precise
namespace/KSA pair and `roles/storage.objectUser` on the existing Ops Bucket.

The Console must reach worker Pod IPs on TCP `8083` and `9090`. The firewall
targets the selected pool's VM service account; other nodes sharing that
identity also receive the allowance. Workers need access to Kafka and outbound
HTTPS for images and the plugin package. Private nodes normally use Cloud NAT.
Enabling CDC also requires worker-to-MySQL DNS and TCP connectivity.

## Connect settings

All settings below are optional. GKE, its node pools, Console, Kafka Instance,
Ops Bucket, and the system plugin remain externally managed.

| Input | Purpose | Default |
| --- | --- | --- |
| `connect_node_pool_name` | Existing pool with spare worker capacity | `default-pool` |
| `console_state_path` | Local Console state | `../terraform/terraform.tfstate` |
| `kafka_state_path` | Local Kafka Instance state | `../automq-cluster/terraform/terraform.tfstate` |
| `console_endpoint_override` | Console address reachable from Terraform | `null`; uses Console state |
| `connect_cluster_name` | Connect Cluster and derived GCP resource name | `gcp-mysql-connect-demo` |
| `connect_namespace` | Dedicated namespace owned by this example | `automq-connect` |
| `connect_service_account` | Worker Kubernetes service account | `automq-connect` |
| `worker_service_account_id` | GSA account ID, not an email | Derived from Connect name |
| `connect_tolerations` | Tolerations matching the selected pool's taints | `[]` |
| `worker_count` | Worker count; does not resize the GKE pool | `1` |
| `worker_resource_spec` | Worker resource tier | `TIER1` |
| `connect_version` | Version from the Console's Connect catalog | `null`; Console default |
| `tags` | AutoMQ resource tags | `{ purpose = "demo" }` |

The Connect worker version is separate from the Console image and Kafka Broker
version. For multiple deployments, use distinct names, namespaces, and GSA IDs.

Every selected pool must use `GKE_METADATA`. For a tainted pool, configure
matching tolerations, for example:

```hcl
connect_node_pool_name = "your-connect-pool"
connect_tolerations = [{
  key      = "dedicated"
  operator = "Equal"
  value    = "automq-connect"
  effect   = "NoSchedule"
}]
```

Leave tolerations empty for an untainted pool. The implementation omits the
empty field because Console 8.4.13 rejects an explicitly empty list.
Cross-project Shared VPC deployments are outside this example.

## MySQL source requirements

- Workers must resolve the MySQL hostname and reach its TCP port, normally
  `3306`. For Cloud SQL private IP, prepare VPC connectivity and database TLS;
  this root does not provision Cloud SQL or grant Cloud SQL IAM roles.
- Enable `log_bin=ON`, `binlog_format=ROW`, and `binlog_row_image=FULL`. Avoid
  `PARTIAL_JSON` in `binlog_row_value_options` and retain binlogs long enough
  for snapshots and recovery.
- Grant the CDC user `SELECT`, `SHOW DATABASES`, `RELOAD`, `REPLICATION SLAVE`,
  and `REPLICATION CLIENT`. Snapshot locking can require `LOCK TABLES` on
  services that restrict global locks. Follow the
  [Debezium MySQL setup guide](https://debezium.io/documentation/reference/3.1/connectors/mysql.html#setting-up-mysql)
  for your database service.
- Choose a `mysql_server_id` unique among the source's replication clients and
  servers. The default is `184054`.
- The default TLS mode, `required`, encrypts traffic without verifying server
  identity. Verify modes also require suitable trust configuration in workers.
- Keep one distinct private anonymous `PLAINTEXT` Kafka bootstrap value in the
  Kafka state's `instance_endpoints`. Debezium history clients use this address
  and their own plaintext producer/consumer configuration.

## MySQL settings

When `create_mysql_connector = true`, `mysql_hostname`, `mysql_user`, and
`mysql_password` are required. A private local tfvars file or
`TF_VAR_mysql_password` can supply the password. Other settings have defaults:

| Input | Purpose | Default |
| --- | --- | --- |
| `create_mysql_connector` | Manage one Connector and its data Topic | `false` |
| `connector_name` | Connector name and history Topic suffix | `mysql-cdc-demo` |
| `mysql_port` | MySQL TCP port | `3306` |
| `mysql_database` | Existing database to capture | `inventory` |
| `mysql_table` | One existing table to capture | `customers` |
| `mysql_server_id` | Replication client ID, from 1 through 4294967295 | `184054` |
| `mysql_ssl_mode` | `disabled`, `preferred`, `required`, `verify_ca`, or `verify_identity` | `required` |
| `topic_prefix` | Data Topic namespace | `mysql-cdc` |

Database and table names accept letters, numbers, and underscores. They select
exactly one table rather than accepting regexes or table lists. Choose unused
Connector and Topic names for this state.

## Consume CDC from GKE

Complete the [worker verification](./README.md#verify-the-workers) first. Run
the following in the same terminal from this directory, after applying the
MySQL Connector. It creates a temporary consumer Pod so your machine does not
need a Kafka CLI or direct access to private Kafka addresses.

Read the Topic name and unique private listener from Terraform outputs. If you
use a custom Kafka state location, adjust the `-chdir` path accordingly:

```bash
CONNECT_NS="$(terraform output -raw connect_namespace)"
CDC_TOPIC="$(terraform output -raw mysql_data_topic)"
CDC_BOOTSTRAP="$(
  terraform -chdir=../automq-cluster/terraform output -json instance_endpoints |
  python3 -c '
import json, sys
values = sorted({
    e["bootstrap_servers"].strip()
    for e in json.load(sys.stdin)
    if e.get("network_type", "").upper() in ("VPC", "PRIVATE")
    and e.get("protocol", "").upper() == "PLAINTEXT"
    and e.get("bootstrap_servers", "").strip()
})
if len(values) != 1:
    raise SystemExit("Expected one distinct private PLAINTEXT Kafka address")
print(values[0])
'
)"
```

This requires Python 3. Stop if either output command fails. The command below
uses `default-pool`; change the node selector if you selected another pool.
For a tainted pool, also add its matching tolerations to `--overrides`.

```bash
CDC_PROBE="cdc-check-$(date +%s)"
kubectl -n "$CONNECT_NS" run "$CDC_PROBE" \
  --image=apache/kafka:3.9.2 \
  --restart=Never --rm -it --pod-running-timeout=180s \
  --overrides='{"spec":{"nodeSelector":{"cloud.google.com/gke-nodepool":"default-pool"},"automountServiceAccountToken":false}}' \
  --command -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server "$CDC_BOOTSTRAP" \
  --topic "$CDC_TOPIC" \
  --group "$CDC_PROBE" \
  --from-beginning \
  --isolation-level read_committed \
  --consumer-property enable.auto.commit=false \
  --consumer-property allow.auto.create.topics=false \
  --property print.key=true
```

Expect snapshot records with `op = "r"`. After the snapshot, write test rows
using an application-write account and check `c`, `u`, and `d` events against
their source keys and values. JSON records omit the `payload` wrapper. Deletes
can also produce null tombstones; retries and history can affect record counts.
Use matching keys and values to verify CDC rather than an exact message count.

Press Ctrl+C to stop. The Pod is removed when the attached command exits. If
an interrupted session leaves it behind, remove only this test Pod:

```bash
kubectl -n "$CONNECT_NS" delete pod "$CDC_PROBE" --ignore-not-found
```

## Troubleshooting

### Credentials or plugin not found

Run `gcloud auth application-default login` for Terraform, then check
`gke-gcloud-auth-plugin --version` in the same shell. A CLI sign-in alone does
not configure ADC. The SDK's `bin` directory must be on `PATH`.

### Console API unavailable

Terraform uses the Console API directly; there is no login-page HTTP check.
Check the Console address, ingress allowlist, and API credentials. Set
`console_endpoint_override` if the address stored in state is not reachable
from your machine. Supporting IAM or Kubernetes resources may already exist
when an API call fails; correct the problem and run `terraform plan` again.

### Missing Ops Bucket output in an older Console state

Use the current Console configuration, which exports `ops_bucket_name`, then
review and publish the output without changing remote resources:

```bash
terraform -chdir=../terraform plan -refresh-only -out=console-refresh.tfplan
terraform -chdir=../terraform apply console-refresh.tfplan
```

### Local provider overrides

If your global Terraform CLI configuration has an `automq/automq`
`dev_overrides` entry, use the pinned Registry release with a separate CLI
configuration:

```bash
cat > terraform.rc <<'EOF'
provider_installation {
  direct {}
}
EOF
export TF_CLI_CONFIG_FILE="$PWD/terraform.rc"
```

Keep this variable set for `init`, `plan`, and `apply` in the same shell.

## Resource ownership

Terraform owns the Connect Cluster, dedicated namespace/KSA, worker GSA,
Workload Identity and bucket bindings, Console-to-worker firewall, and optional
MySQL Connector and single-partition data Topic. Deleting the namespace also
removes resources added to it outside Terraform. The IAM Service Account
Credentials API remains enabled after destroy.

The data Topic is `<topic_prefix>.<mysql_database>.<mysql_table>`. To use an
existing Topic, explicitly transfer sole ownership before importing it into
this state. Do not manage a Topic from multiple states.

Debezium owns `schema-history.<connector_name>`, with one partition and
unbounded retention. Its retention requirements exceed the Console Topic
API's limit, so this Topic remains outside Terraform. Preserve it for recovery
and keep it exclusive to the Connector. See the
[Debezium 3.1.2 implementation](https://github.com/debezium/debezium/blob/v3.1.2.Final/debezium-storage/debezium-storage-kafka/src/main/java/io/debezium/storage/kafka/history/KafkaSchemaHistory.java#L479).

`mysql_schema_history_topic` reports a configured name, not proof of Topic
creation. The MySQL outputs are null when CDC is disabled. Mock-provider tests
check Terraform contracts; actual worker startup, plugin loading, telemetry
delivery to the Ops Bucket, and CDC need runtime verification.
