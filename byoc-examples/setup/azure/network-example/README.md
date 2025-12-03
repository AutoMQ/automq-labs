# Azure Network Example for AutoMQ

Standalone Terraform example to create a VNet with public/private subnets and NAT for AutoMQ AKS deployments.

## Prerequisites
- Terraform >= 1.3
- Azure CLI logged in (`az login`)

## Usage
1. Prepare `terraform.tfvars` (example):
```hcl
subscription_id     = "<subscription-guid>"
resource_group_name = "automq-network-rg"
location            = "eastus"
vnet_cidr           = "10.0.0.0/16"
name_suffix         = "automq-net"
```
2. Run:
```bash
terraform init
terraform plan
terraform apply
```

## Outputs
- `resource_group_name`
- `vnet_id`
- `private_subnet_id`
- `public_subnet_id`
