# Configuration reference

Use the [deployment guide](../README.md) for the standard path. This page explains the available inputs and the deployment choices that may require a different example or additional preparation.

## Terraform inputs

Each directory is a separate Terraform root. Put non-secret inputs in its own `terraform.tfvars`; supply secrets through environment variables. Values in `.tfvars.example` are samples to replace, not resources that exist in your account.

### Foundation: `infrastructure/`

| Input | Required or default | Meaning and selection |
| --- | --- | --- |
| `automq_config` | Required; use `TF_VAR_automq_config` | Complete AWS BYOC `CONFIG` from AutoMQ. It carries the Environment, Region, client identity and Ops bucket; it is not an AWS access key |
| `vpc_id` | Required | Existing VPC in the CONFIG Region; this root does not take ownership of it |
| `private_subnet_ids_by_az` | Required | Exactly three distinct AZ-to-private-subnet pairs, in the selected VPC |
| `s3_vpc_endpoint_id` | Required | S3 Gateway Endpoint associated with each selected private route table, permitting Ops and future managed Data buckets |
| `deployer_role_arn` | Required | IAM role ARN used to administer this EKS cluster; must match the role used by your deployment session. Do not use an STS assumed-role session ARN or the Console role |
| `name_prefix` | `automq-eks-demo` | Unique lowercase resource prefix, 3–30 characters, starting with a letter |
| `kubernetes_version` | `1.36` | Keep `1.36` for this example. Console checks this exact version; changing it requires updating and verifying the component configuration together |
| `public_api_allowed_cidrs` | `[]` | Empty disables the public API. Set only trusted IPv4 CIDRs when the deployment host cannot reach the private API; `0.0.0.0/0` is rejected |
| `service_ipv4_cidr` | `172.20.0.0/16` | Kubernetes Service address space; use a canonical private `/12`–`/24` range that does not overlap any VPC CIDR |
| `system_instance_type` | `m7i.large` | x86 system-node size; leave capacity for Console's 1 vCPU/4 GiB request and system components |
| `system_max_nodes` | `4` | System node-pool maximum, at least 2; initial size is two On-Demand nodes |
| `automq_instance_type` | `m7g.xlarge` | ARM Graviton worker-node size compatible with the selected AutoMQ specification; also set the same Instance `instance_type` |
| `automq_max_nodes_per_az` | `4` | Worker-node maximum in each AZ, at least 1; initial size is one On-Demand node per AZ |
| `addon_versions` | `{}` | Optional map of exact versions for `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`. Omitted entries resolve an EKS-compatible version at deployment. Save the resolved `addon_versions` output to reproduce your environment |
| `console_namespace` | `automq-console` | Console namespace; substitute it in all Console kubectl commands if changed |
| `console_service_account_name` | `automq-console` | Console Kubernetes ServiceAccount, referenced by its IRSA trust and Helm release |
| `create_private_nat_egress` | `false` | Explicit opt-in to create an owned NAT/EIP and missing private default routes; see [NAT configuration](#optional-nat-for-an-existing-network) |
| `nat_public_subnet_id` | `null` | Required when NAT opt-in is enabled; existing public subnet in this VPC with a default route to its attached Internet Gateway |

The business pools use `AL2023_ARM_64_STANDARD`; the system pool uses `AL2023_x86_64_STANDARD`. Select compatible images and Instance specifications for their respective architectures. The node-pool autoscaler supplies capacity for pending Pods within these limits; an Instance's configured node count is a separate setting.

For sizing and placement requirements, review the official [EKS compute-capacity guide](https://docs.automq.com/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks#step-3-prepare-eks-compute-capacity) and [SchedulingSpec reference](https://docs.automq.com/automq-cloud/deploy-automq-on-kubernetes/overview#schedulingspec). This example creates its pools and scheduling automatically with `automq.io/pool` labels; retain those selectors when adapting capacity rather than copying the manual guide's different labels.

### Console: `console/`

| Input | Required or default | Meaning and selection |
| --- | --- | --- |
| `automq_config` | Required; `TF_VAR_automq_config` | Same complete CONFIG as the foundation; Environment, Region and Ops bucket must match |
| `console_image` | Required | Compatible `repository:tag` supplied by AutoMQ. This example has no compatible image default and rejects `latest`, `8.3.28` and `8.3.28-aws` |
| `infrastructure_state_path` | `../infrastructure/terraform.tfstate` | Foundation state path, resolved from `console/` |
| `console_chart_path` | `null` | Optional local copy of the official pinned Chart for offline installation/validation. Default pulls the OCI Chart |
| `deployer_assume_role_arn` | `null` | Optional explicit alternate-role path for AWS EKS token generation. The default uses the current profile session directly; use an authorized deployment role, never the Console role |

The `scripts/kubectl.py` wrapper uses the foundation cluster and current AWS profile directly. If using an alternate deployer role, assume that role before invoking the wrapper. It does not apply `deployer_assume_role_arn` itself or use your current Kubernetes context.

The Console persists state on an encrypted 20 GiB gp3 EBS volume. Its Service is ClusterIP, and ingress is disabled. Storage size, Chart versions, Console resources and Instance security features are explicit values in the Terraform code rather than additional `.tfvars` inputs. Review their configuration before adapting the example.

### Instance: `automq-example/instance/`

| Input | Required or default | Meaning and selection |
| --- | --- | --- |
| `automq_version` | Required | Data-plane version available in the initialized Console; use the selected Kafka Instance release, not a Console 8.x version |
| `instance_name` | `aws-eks-managed-demo` | Display name for the new Kafka Instance |
| `instance_type` | `m7g.xlarge` | Supported Instance specification matching foundation `automq_instance_type` |
| `infrastructure_state_path` | `../../infrastructure/terraform.tfstate` | Foundation state path, resolved from this directory |

Set `AUTOMQ_BYOC_ENDPOINT`, `AUTOMQ_BYOC_ACCESS_KEY` and `AUTOMQ_BYOC_SECRET_KEY` in the environment for the AutoMQ provider. Create these keys using an AutoMQ management Service Account with the required permissions.

The root creates three nodes across the three foundation AZs, with UsageBased pricing, S3WAL and SASL_PLAINTEXT. It reads the cluster **name**, private NLB subnets and business-pool scheduling from foundation state. It omits Data bucket, IAM role, DNS and namespace/ServiceAccount inputs so Console owns their lifecycle.

### Kafka verification: `automq-example/smoke/`

| Input | Required or default | Meaning and selection |
| --- | --- | --- |
| `kafka_password` | Required; `TF_VAR_kafka_password` | Dedicated Kafka user password, at least 16 characters and no line breaks |
| `instance_state_path` | `../instance/terraform.tfstate` | Instance state path, resolved from the smoke directory |

Use the same management endpoint and keys as the Instance root. The smoke root creates Topic `eks-smoke`, user `eks-smoke`, a literal Topic ACL and a Consumer group ACL for names starting with `eks-smoke-`.

Only the Kafka client needs `KAFKA_BOOTSTRAP_SERVERS` and `TF_VAR_kafka_password`. Copy the exact private `SASL_PLAINTEXT` bootstrap address, including its port, from the Instance output. The client does not need AWS credentials, Terraform state or AutoMQ management keys.

## Network options

### Optional new network

Use `network-example/` if you need a separate VPC. It creates a VPC with three public/private subnet pairs, an Internet Gateway, a single NAT gateway and an S3 Gateway Endpoint. Run it before the foundation and destroy it after all AutoMQ resources.

```bash
cp network-example/terraform.tfvars.example network-example/terraform.tfvars
# Set region and availability_zones to match your AutoMQ CONFIG.
terraform -chdir=network-example init
terraform -chdir=network-example plan -out=network.tfplan
terraform -chdir=network-example apply network.tfplan
terraform -chdir=network-example output
```

Copy `vpc_id`, `private_subnet_ids_by_az` and `s3_vpc_endpoint_id` into `infrastructure/terraform.tfvars`. Keep `create_private_nat_egress=false` in the foundation because this network already has outbound routing.

| Input | Required or default | Selection |
| --- | --- | --- |
| `region` | Required | Same Region as CONFIG |
| `availability_zones` | Required | Exactly three distinct AZ names in that Region |
| `name_prefix` | `automq-eks-demo` | Unique prefix for network resources |
| `vpc_cidr` | `10.42.0.0/16` | IPv4 `/16`–`/20` range that does not overlap connected networks or the Kubernetes Service CIDR |

### Optional NAT for an existing network

The foundation normally requires existing outbound routing. If the three selected private route tables have no default route, you may explicitly set:

```hcl
create_private_nat_egress = true
nat_public_subnet_id      = "subnet-0123456789abcdef3"
```

The public subnet must be in the same VPC and route to an attached Internet Gateway. The foundation creates its own EIP/NAT and missing default routes, and removes only those resources at destruction. It never replaces or adopts a foreign default route.

One NAT is a cost/availability tradeoff: an AZ or NAT failure affects outbound access for all three AZs, and cross-AZ traffic can incur charges. A route conflict can fail after the NAT/EIP has been created; inspect Terraform state and AWS before retrying. Keep the NAT enabled while workloads depend on it.

### EKS API and Kafka access

The EKS API is private by default. Run deployment commands on a VPC-connected machine, or configure `public_api_allowed_cidrs` with an explicitly trusted source such as your workstation's public `/32`. That public endpoint is for EKS administration; it does not expose Kafka or Console.

Console access defaults to a localhost port-forward. Kafka requires independent private DNS and routing to every broker endpoint. Use a VPC client or a routed, DNS-enabled connection to the VPC. For a persistent Console endpoint, follow the [optional HTTPS ALB procedure](operations.md#optional-console-https-endpoint).

## Permission and deployment choices

Choose the combination that matches your resource-management policy. The deployment guide implements one path: **Default Permissions, Helm Console, managed K8S Instance and IRSA**.

| Permission mode | Resource preparation | Suitable path |
| --- | --- | --- |
| Default Permissions | Console can create and manage Instance Data buckets, roles and private DNS, or use explicitly supplied existing resources | This example selects automatic Instance resource management |
| EC2 Mode Minimal Permissions | You prepare the resources and grant the exported EC2 permissions | [EC2 deployment example](../../ec2/README.md) |
| EKS Mode Minimal Permissions | You prepare the Data bucket, data-plane role/identity, DNS and required namespace/ServiceAccount prerequisites, and grant the exported K8S permissions | Adapt the [existing EKS example](../../eks-existing/README.md) to the selected mode |

For EKS Minimal, change the Instance inputs to supply `data_buckets`, `instance_role`, `dns_zone` and required Kubernetes identity fields. Changing only the Console policy while leaving this managed root's resource fields omitted does not prepare those resources. Check the selected mode's exported policy during System Initialization and the [Instance provider schema](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance).

| Choice | Selected here | Alternatives |
| --- | --- | --- |
| Console deployment | Official Helm Chart on EKS system nodes | VM/Docker; see the [EC2 Console example](../../ec2/README.md) |
| Instance deployment | Console-managed K8S Instance | EC2/ASG; this is a different Instance deployment path |
| Console Kubernetes access | In-cluster Kubernetes ServiceAccount + ClusterRoleBinding to `cluster-admin` | IAM principal + EKS Access Entry/EKS access policy; requires a compatible Console path and separate access configuration |
| AWS workload credentials | IRSA for Console, each Instance and infrastructure components | AWS EKS Pod Identity is a distinct mechanism requiring separate compatibility validation |

### AWS and management permissions

For Console's required AWS permissions, see [Complete Console initialization](https://docs.automq.com/automq-cloud/getting-started/install-byoc-environment/aws/install-automq-on-aws#complete-initialization), which explains the IAM policy displayed during initialization. This example's [foundation IAM configuration](../infrastructure/iam.tf) already provisions the Console role and policies. Use the official manual-grant steps to understand and review those permissions; a second manual role/policy setup is not needed for this path.

For AWS role and workload-identity preparation, see the official [Console workload-identity guide](https://docs.automq.com/automq-cloud/getting-started/install-byoc-environment/aws/install-automq-on-aws#configure-the-workload-identity) and [Instance IAM role and ServiceAccount guide](https://docs.automq.com/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks#step-5-prepare-the-automq-workload-iam-role-and-serviceaccount). Their manual provisioning and alternative identity paths explain the underlying requirements; these Terraform roots retain Console ServiceAccount/RBAC, IRSA and Console-managed Instance resources. AutoMQ [management Service Accounts](https://docs.automq.com/automq-cloud/manage-identities-and-access/service-accounts) grant management API access and are separate from AWS IAM roles.

The deployer has its own EKS Access Entry, independent of Console. IRSA is a Pod-level identity mechanism; it is not the AWS EKS Pod Identity product. Default Permissions and `cluster-admin` are broad permissions for resource management. Pod identity isolation does not by itself make the permission set least-privilege: review the [foundation IAM policies](../infrastructure/iam.tf) against your security requirements. Nodes receive worker/ECR policies only, while business permissions stay on their workload roles. IMDSv2 with hop limit 1 restricts ordinary Pod access to Node credentials; hostNetwork/infrastructure Pods need separate review.

## Component versions

Use the supplied versions as a coordinated configuration. Console Chart and image versions are different inputs, and the data-plane version is chosen from Console.

| Component | Version or selection |
| --- | --- |
| Terraform | `>= 1.9, < 2.0`; CI uses `1.11.4` |
| EKS | `1.36` |
| Terraform EKS module | `21.2.0` |
| AWS / TLS providers | `6.13.0` / `4.1.0` |
| Kubernetes / Helm providers | `2.38.0` / `2.17.0` |
| Console Chart | `oci://automq.azurecr.io/helm/automq-byoc-console-chart`, `8.3.28` |
| Console image | Explicit compatible image from AutoMQ; no default |
| AWS Load Balancer Controller | Chart `1.13.4`, controller `2.13.4` |
| Cluster Autoscaler | Chart `9.59.0`, image `v1.36.0` |
| EKS add-ons | Compatible versions resolved during deployment, or exact `addon_versions` inputs |
| AutoMQ Terraform provider | `0.4.8` |
| Data plane | Explicit `automq_version` available in the initialized Console |

The Autoscaler image is explicitly aligned to EKS 1.36. Node AMI releases and default add-on resolution can change between deployments; retain your applied versions and AMI IDs with the deployment record when reproducibility is required.

## State and credentials

Each root owns its own Terraform state. The defaults use the adjacent state paths in the tables. If changing to a team remote backend, configure the backend and every dependent state handoff together; Terraform remote-state access grants access to the full source state, including sensitive values.

`CONFIG`, AutoMQ management keys and Kafka passwords must remain outside Git and command arguments. Terraform state and saved plans can contain plaintext secrets despite sensitive-output redaction. Use `umask 077`, encrypted storage and restricted access/backups. Kubernetes Secret encryption and authorization need the same protection. Keep shell tracing and `TF_LOG` disabled.

The four identities have different purposes:

| Identity | Used for |
| --- | --- |
| AWS deployment profile/role | Provisioning AWS resources and installing Kubernetes/Helm resources |
| Kubernetes ServiceAccount and IRSA role | Console, Instance and component runtime authorization |
| AutoMQ management Service Account/access keys | Terraform management API requests for Instance/Topic/user/ACL lifecycle |
| Kafka user/password | Application produce/consume authentication |
