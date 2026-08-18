# Moved: AutoMQ on Amazon EC2

The AWS EC2 quick-start has moved to [`../ec2/README.md`](../ec2/README.md).
Use the `ec2` directory for new deployments.

If you already ran Terraform from this legacy directory, move each root
module's local state, `.terraform` directory, generated auto tfvars, and any
uncommitted `terraform.tfvars` to the matching directory under `../ec2/` before
running Terraform there. Remote-state users should initialize the new path
with the same backend configuration. Do not apply from a fresh state against
resources managed by the old state.
