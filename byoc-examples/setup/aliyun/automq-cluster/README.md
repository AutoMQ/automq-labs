# Create an AutoMQ Elastic Pool on Alibaba Cloud

This standalone Terraform example creates one AutoMQ Instance in an existing
Alibaba Cloud BYOC environment. The resulting Instance is the Elastic Pool; the
Terraform resource label is `elastic_pool` to make that relationship explicit.

The example configures:

- VMIS deployment across three availability zones.
- One existing VSwitch/subnet in each availability zone.
- Regional ESSD-backed WAL through the Provider's `EBSWAL` API value.
- An existing security group, OSS data bucket, PrivateZone, and RAM role.
- Exactly two custom resource tags.
- AutoMQ Provider endpoint and Service Account credentials supplied through a
  separate `terraform.tfvars` file.

## Provider terminology

The AutoMQ Provider uses `deploy_type = "IAAS"` for VMIS deployments and
`wal_mode = "EBSWAL"` for block-storage-backed WAL. In Alibaba Cloud, the latter
is implemented with Regional ESSD. VSwitch IDs are also the subnet identifiers
passed in each `networks` entry.

## Prerequisites

- Terraform 1.3 or later.
- An installed Alibaba Cloud AutoMQ BYOC environment.
- AutoMQ data plane version 5.5.2 or later for Regional ESSD cross-AZ failover.
- An AutoMQ Service Account with an Access Key.
- Three existing VSwitches in three availability zones of the environment VPC.
- An existing security group, OSS data bucket, PrivateZone, and data-plane RAM
  role configured for AutoMQ.

## Configure

Create the local configuration file from the committed example:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and replace every value marked `REPLACE_ME`. Keep the
three zone IDs aligned with their VSwitch IDs.

The local `terraform.tfvars` file is ignored by Git so real Access Key values
are not committed to source control.

## Create

```bash
terraform init
terraform plan
terraform apply
```

## Outputs

```bash
terraform output -raw elastic_pool_id
terraform output elastic_pool_status
terraform output -json elastic_pool_endpoints
```

## Cleanup

```bash
terraform destroy
```

Destroying this Terraform configuration deletes only the AutoMQ Instance. It
does not delete the referenced VSwitches, security group, data bucket, DNS zone,
or RAM role.
