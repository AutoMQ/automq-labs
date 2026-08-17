# AutoMQ on Amazon EC2

This example deploys an AutoMQ BYOC Console AMI and creates an AutoMQ data
plane on Amazon EC2. It is intended for demos and evaluation, not as a
production architecture.

The example has two Terraform root modules and therefore two independent state
files:

1. `automq-console` creates the Console EC2 instance, S3 data bucket, private
   Route 53 zone, Console IAM role, and a separate EC2 data-plane role.
2. `automq-cluster` uses the AutoMQ Terraform Provider to create an IAAS AutoMQ
   Instance after the Console is ready.

`modules/automq-role` is called by `automq-console`; do not deploy it as a third
Terraform state.

## Prerequisites

- Terraform 1.5.7 or later.
- AWS credentials with permission to create the resources in this example.
- An existing VPC, one public subnet for the Console, and one private broker
  subnet in each of either one or three availability zones. The private subnets
  need outbound access to the AWS and AutoMQ services used by the data plane.
- The AutoMQ BYOC Installation Script values for `ENVIRONMENT_ID`, `CLIENT_ID`,
  `CLIENT_SECRET`, and the ops bucket name from `CONFIG.opsBucket.bucketName`.
- The exact AutoMQ Console AMI name and trusted AWS owner account for the target
  region. Ask AutoMQ for these AMI details; the example deliberately does not
  select an arbitrary owner or wildcard AMI.
- AutoMQ Terraform Provider `0.4.5`, which is pinned and installed by the
  Cluster root module.

The Console UI and SSH CIDR allowlists are required. Replace the documentation
CIDRs in the example instead of opening the ports to `0.0.0.0/0`.

## 1. Deploy the Console

```bash
cd automq-console
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`, then deploy:

```bash
terraform init
terraform plan
terraform apply
```

Get the Console endpoint and initial credentials:

```bash
terraform output -raw console_endpoint
terraform output -raw console_initial_username
terraform output -raw console_initial_password
```

Open the endpoint and sign in. An EC2 `running` state does not mean the Console
application is ready; wait until the login page responds and the UI is usable
before continuing. The AMI's initial password is the Console EC2 instance ID.

## 2. Configure the Cluster

Copy the Cluster example in a second terminal:

```bash
cd ../automq-cluster
cp terraform.tfvars.example terraform.tfvars
```

Populate its variables from the `automq-console` state:

| `automq-cluster` input | `automq-console` output |
| --- | --- |
| `console_endpoint` | `console_endpoint` |
| `console_access_key` | `console_initial_access_key` |
| `console_secret_key` | `console_initial_secret_key` |
| `environment_id` | `environment_id` |
| `private_subnet_ids_by_zone` | `private_subnet_ids_by_zone` |
| `data_bucket_name` | `data_bucket_name` |
| `dns_zone_id` | `dns_zone_id` |
| `instance_role_arn` | `cluster_role_arn` |

For example, read sensitive values explicitly from the Console directory:

```bash
terraform -chdir=../automq-console output -raw console_initial_access_key
terraform -chdir=../automq-console output -raw console_initial_secret_key
terraform -chdir=../automq-console output -json private_subnet_ids_by_zone
```

Set `automq_version` to an exact data-plane version available in this Console.
The example currently uses `5.5.3`, the stable version validated with this
configuration. Do not infer a version by sorting strings or silently fall back
to another version.

The default Cluster is a three-AKU, subscription-based IAAS deployment using
EBSWAL with anonymous plaintext access inside the VPC.

## 3. Create and Verify the Cluster

```bash
terraform init
terraform plan
terraform apply
```

Inspect the Instance state and endpoints:

```bash
terraform output -raw instance_id
terraform output -raw instance_status
terraform output -json instance_endpoints
```

Wait for the Instance to reach its running state. Terraform completion proves
that the Control Plane accepted the Instance; it does not prove Kafka client
traffic. From a host with network access to the private endpoint, run a Kafka
produce/consume smoke test against a temporary topic:

```bash
kafka-topics.sh --bootstrap-server <bootstrap-servers> --create \
  --topic automq-ec2-smoke --partitions 3 --replication-factor 3
printf 'automq-ec2-smoke\n' | kafka-console-producer.sh \
  --bootstrap-server <bootstrap-servers> --topic automq-ec2-smoke
kafka-console-consumer.sh --bootstrap-server <bootstrap-servers> \
  --topic automq-ec2-smoke --from-beginning --max-messages 1
```

## State and Credentials

Both states contain secrets, including BYOC credentials, generated Console API
credentials, and the SSH private key. Use encrypted remote state with restricted
access. Do not commit `terraform.tfvars`, state files, plans, or credentials.

The previous flat `ec2-custom` configuration is not state-compatible with this
layout. Destroy it with the old revision before switching, or use new backend
keys/workspaces for both new root modules. Do not point an old state at these
directories and apply it in place.

## Cleanup

Destroy the Cluster state first so the data plane no longer depends on the IAM,
DNS, subnet, and bucket resources owned by the Console state:

```bash
cd automq-cluster
terraform destroy

cd ../automq-console
terraform destroy
```

By default, a data bucket created by this demo uses `force_destroy = true` and
its objects are deleted during cleanup. An existing data bucket and the existing
ops bucket are not owned or deleted by this example.
