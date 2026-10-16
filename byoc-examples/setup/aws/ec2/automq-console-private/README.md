# AutoMQ Console on Amazon EC2: Pure Private Network

This is a separate Terraform template for a pure private deployment. It does
not modify or share state with the standard `automq-console` template.

The template creates the Console and broker subnets without an internet
gateway, NAT Gateway, public IP, or EIP. S3 uses a Gateway VPC Endpoint, and
the VPC contains the selected AWS API Interface Endpoints plus the AutoMQ Home
PrivateLink service:

`com.amazonaws.vpce.us-east-1.vpce-svc-0a654212125c7872a`

The endpoint set is selected by `cluster_mode` and the feature flags in
`terraform.tfvars`:

| Setting | Endpoints added |
| --- | --- |
| Always | EC2, Route 53, IAM |
| `cluster_mode = "ec2"` | Auto Scaling |
| `cluster_mode = "eks"` | EKS, Elastic Load Balancing |
| `enable_fsx = true` | FSx |
| `enable_efs = true` | EFS |
| `enable_s3table = true` | S3 Tables (`s3tables`) |
| `enable_public_dns = true` | STS |

Because this service endpoint is in `us-east-1`, the AutoMQ `CONFIG` Region
must also be `us-east-1`.

This template enables Private DNS for the AutoMQ Home endpoint. The Endpoint
Service must therefore have a provider-verified Private DNS Name configured by
AutoMQ; AWS rejects the endpoint if that service-side configuration is absent.

Before applying, make sure the private subnet can obtain the Amazon Linux
bootstrap packages and pull the Console image through an approved private
path. The generated `console_endpoint` is an HTTP URL using the instance's
private IP and is reachable only from connected private networks.

```bash
cp terraform.tfvars.example terraform.tfvars
# Set automq_config in terraform.tfvars.
terraform init
terraform plan
terraform apply
terraform output -raw console_endpoint
```

The Cluster stage can use `../automq-cluster` after the private Console is
initialized, but it must read this template's separate state file. Set the
following in `automq-cluster/terraform.tfvars`:

```hcl
console_state_path = "../automq-console-private/terraform.tfstate"
```

Run Cluster Terraform from a machine with private network access to the
Console endpoint; the Cluster provider calls the Console API over its private
IP.
