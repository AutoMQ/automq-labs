# AutoMQ BYOC Console on GCP

This Terraform example deploys the AutoMQ BYOC Console into an existing GCP VPC
and subnet. It is intentionally separate from GKE provisioning so the Console
and Kubernetes infrastructure have independent Terraform state and lifecycle.

## Resources

- An AutoMQ Console VM with a static public endpoint and persistent data disk.
- A Console service account and its GCP control-plane permissions.
- A custom role for Cloud DNS managed-zone IAM policy operations.
- A firewall rule for public Console access on TCP port 8080.
- Generated initial Console and AutoMQ Terraform provider credentials.

The Console creates the environment Ops Bucket during bootstrap and creates
each Instance's Data Bucket and DNS Zone when the Instance is created.

This example does not create a VPC or GKE cluster. Use the
[GKE Terraform example](../../kubernetes/gcp/terraform/) first, or provide an
existing VPC and subnet.

## Prerequisites

- Terraform 1.3 or later.
- `gcloud`.
- A GCP project with billing enabled.
- A GCP BYOC installation configuration from AutoMQ containing the base64
  `CONFIG` value and Console image.
- Application Default Credentials:

  ```bash
  gcloud auth application-default login
  ```

- `serviceusage.googleapis.com` and `compute.googleapis.com` enabled before
  running Terraform. Terraform enables the Resource Manager, Cloud DNS, IAM,
  and Cloud Storage APIs and leaves them enabled during destroy.
- Permissions to enable project services and create Compute Engine, IAM,
  Cloud DNS, and GCS resources.

## Deploy

1. Create a local variables file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Set `project_id`, `region`, `zone`, `network_id`,
   `management_subnet_id`, `automq_config`, and `automq_console_image`.

3. If the Console image is private, also set all fields in
   `automq_console_registry`.

4. Initialize, review, and apply:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

5. Open the Console:

   ```bash
   terraform output -raw console_endpoint
   terraform output -raw console_initial_password
   ```

   The initial username is `admin`.

## AutoMQ Provider

The Console generates an initial access key pair for automation:

```bash
terraform output -raw console_endpoint
terraform output -raw console_initial_access_key
terraform output -raw console_initial_secret_key
terraform output -raw automq_environment_id
```

Use these values with provider `automq/automq` to create an
`automq_kafka_instance`. See the standalone
[AutoMQ Instance example](../automq-cluster/) for a minimal GKE configuration.

## Configuration

| Input | Description | Default |
| --- | --- | --- |
| `project_id` | GCP project for Console resources | Required |
| `region` | Region for regional Console resources | Required |
| `zone` | Zone for the Console VM and data disk | Required |
| `network_id` | Existing VPC canonical resource ID | Required |
| `management_subnet_id` | Existing Console subnet canonical resource ID | Required |
| `name_prefix` | Prefix for generated resource names | `automq` |
| `automq_config` | Base64 `CONFIG` value from AutoMQ | Required |
| `automq_console_image` | GCP Console container image from AutoMQ | Required |
| `automq_home_endpoint` | AutoMQ Cloud endpoint | `https://console.automq.cloud` |
| `automq_console_registry` | Optional private registry credentials | Empty |
| `console_machine_type` | Console VM machine type | `e2-standard-2` |
| `console_ingress_source_ranges` | CIDRs allowed to access TCP port 8080 | `0.0.0.0/0` |

## Security Notes

The Console endpoint is public so the example is easy to access. Restrict
`console_ingress_source_ranges` to trusted public CIDRs.

The Console service account uses broad control-plane permissions so it can
manage GKE, IAM, DNS, and Instance resources. The bootstrap client secret,
registry password, and generated Console credentials are stored in Terraform
state and GCE instance metadata. Protect the state and use a hardened
secret-delivery and IAM design for production.

## Cleanup

Delete AutoMQ Instances managed by the Console before destroying it:

```bash
terraform destroy
```

The Console-created Ops Bucket is outside Terraform state; delete it separately
after the environment is no longer used.
