# New EKS with Helm Console and a managed Kafka Instance

This evaluation example creates a new EKS cluster in an existing VPC, installs the AutoMQ BYOC Console through its official Helm Chart, and creates a three-AZ managed K8S Instance. The final check writes and reads a unique Kafka record over a private SASL_PLAINTEXT endpoint. Existing AWS examples remain separate: [EC2](../ec2/README.md), [legacy EKS](../eks/README.md), and [existing EKS](../eks-existing/README.md).

The default combination is **Default Permissions + Helm Console + K8S Instance + IRSA**. Console uses its Pod ServiceAccount and Kubernetes RBAC to manage this same cluster. Its separate IRSA role provides Pod-level AWS API credentials; IRSA is distinct from the AWS EKS Pod Identity product. Console's KSA has a ClusterRoleBinding to Kubernetes `cluster-admin`. The deployer's AWS session is a third identity.

## Compatibility and prerequisites

| Component | This example |
| --- | --- |
| Terraform | >= 1.9; local checks use 1.11.4 |
| EKS / AWS provider | 1.36 / 6.13.0; see infrastructure lockfile |
| Kubernetes / Helm providers | 2.38.0 / 2.17.0 |
| Console Chart | `oci://automq.azurecr.io/helm/automq-byoc-console-chart`, `8.3.28` |
| Console image | Required explicit `console_image`; see the release prerequisite below |
| AWS Load Balancer Controller | Chart 1.13.4, controller v2.13.4; matches the foundation IAM policy |
| Cluster Autoscaler | Chart 9.59.0 with explicit image `registry.k8s.io/autoscaling/cluster-autoscaler:v1.36.0` |
| AutoMQ provider | 0.4.8 |
| Data-plane version | Required `automq_version`, selected from the initialized Console; independent of Console 8.x |
| Capacity | Two On-Demand `m7i.large` system nodes; one On-Demand `m7g.xlarge` per business AZ, with autoscaling limits |

**Release prerequisite:** use a Console image that includes in-cluster ServiceAccount management support, exact namespace/ServiceAccount IRSA trust with safe managed-role reconciliation, and the K8S S3WAL policy change that removes unnecessary EC2 volume permissions. These changes are an unreleased product dependency. Chart 8.3.28 is published and was pulled/rendered locally; its matching old `8.3.28-aws` image lacks the selected ServiceAccount path and is rejected. An explicitly supplied compatibility test image needs source/build provenance and runtime verification; local tests alone do not certify a release. This example does not supply a compatible image default or bypass License, subscription, or initialization checks.

### Observed live combination — 2026-11-16

The first live evaluation used the following resolved versions. This is a historical test record, not a formal support certification or a promise that these versions remain available.

| Component | Observed version or configuration |
| --- | --- |
| EKS control plane / Node kubelet | `1.36` / `v1.36.5-eks-9adbfea` |
| System / business Node image families | `AL2023_x86_64_STANDARD` / `AL2023_ARM_64_STANDARD` |
| Node OS / runtime | Amazon Linux `2023.12.20261112` / `containerd://2.3.7+unknown` |
| VPC CNI | `v1.23.3-eksbuild.1` |
| CoreDNS | `v1.14.7-eksbuild.35` |
| kube-proxy | `v1.36.0-eksbuild.65` |
| EBS CSI | `v1.68.0-eksbuild.1` |
| Console | Chart `8.3.28` + full AWS production compatibility build `8.4.0-SNAPSHOT`, `linux/amd64` |
| Console source | Baseline `8284ae66430e1ecdb34eac812cc505ea552524b6`, with strict managed IRSA trust and K8S S3WAL policy patches |
| Data plane | `5.5.5`, AWS/POD, S3WAL, `m7g.xlarge` |
| Kafka test client | `confluent-kafka` `2.16.1` |

The Console test artifact had Jar SHA-256 `b14781bc6541f476609f585a7597fcf830b28f55e479e668b1f29b9b59a4f0de` and OCI digest `sha256:729a07b935ee29095fe3133a2455c0c63828524927967bb0ec075d07060bb4a4`. These identify an unreleased compatibility build; they do not identify a public image or provide a default image to pull. Supply a formal release with the required capabilities, or a compatible build with equivalent source/build provenance and runtime verification.

The initial run verified three-AZ node placement, strict Pod identity checks, Console PVC persistence, two unique private Kafka markers, and scale-out followed by automatic return. Reconstruction from an empty foundation also completed: the foundation, Console and managed Instance were recreated, and a third unique private Kafka marker passed. Final cleanup of the reconstructed environment completed, including removal of the test ECR repository; the final 26 cloud-absence checks passed. The two EKS-owned KMS keys remain in `PendingDeletion` with scheduled deletion on 2026-12-16; this mandatory waiting window is recorded rather than reported as immediate key removal. The existing customer network and pre-existing VM were retained. The data-plane version remains an explicit user input selected from the initialized Console; `5.5.5` is only the observed test version. Node AMI releases and default add-on resolution can change on later deployments. To reproduce the add-on combination, pass the recorded `addon_versions` output values explicitly; also record the actual Node AMI IDs/releases rather than treating this table as an AMI pin.

Install AWS CLI v2, Terraform, kubectl, Helm 3, Python 3 and PyYAML. The deploying machine must reach the configured EKS API endpoint on 443 and the Console's localhost port-forward. The API is private by default; that path requires VPC connectivity. Alternatively, explicitly enable the public API with trusted source CIDRs (such as the deployer's current public `/32`) and verify the actual allowed source. A deployer using that restricted public endpoint does not need a VPN solely for Kubernetes API access. A private Kafka client must also resolve the managed private DNS and reach all advertised broker endpoints; reaching only a bootstrap address is insufficient. Use a VPC host or a routed VPN/connected network with the required DNS forwarding and security rules. This example does not create a public Kafka endpoint.

Obtain a complete AWS BYOC CONFIG and a valid subscription. Use a **new BYOC Environment** and CONFIG that no active Console is using. Before deployment, read the Ops bucket name from CONFIG without exposing the full CONFIG, and perform an S3 `HeadBucket` check in the intended account. Continue this new-environment flow only after an authoritative `404` confirms that the bucket does not exist. A `403` or insufficient permission does not establish absence. If the bucket already exists, stop and confirm its owner, Terraform state and whether another Console still uses it; use an explicit migration/import plan or create a new Environment. Do not apply this fresh-environment root and assume ownership of an existing bucket. In `us-east-1`, `CreateBucket` can return success for an existing same-account bucket, so a Terraform plan showing `create` is not ownership evidence. Choose an AWS profile with foundation provisioning permissions and the IAM role configured as `deployer_role_arn`. That role receives EKS access independently of Console. `aws eks get-token` uses the current profile session by default: it does not unconditionally self-assume the role. `console.deployer_assume_role_arn` is only for an explicitly configured alternate assume-role path. Do not use a personal cloud access key, the Node role, or an IAM kubeconfig inside the Console Pod to replace its ServiceAccount.

### Network contract

Provide one private subnet in each of three distinct AZs, in the same VPC and CONFIG Region, with DNS enabled and an S3 Gateway Endpoint associated with every selected private route table. The endpoint policy must permit the Ops bucket and future CMP-managed Data buckets. Nodes also need general outbound access to EKS/ECR/STS and required registries; S3 access alone cannot bootstrap the environment. Service CIDR must not overlap any VPC CIDR. The optional [network-example](network-example/main.tf) creates a separate evaluation network; use its outputs as foundation inputs.

Existing networks are read and checked; this example does not import or take ownership of their VPC, subnets, route tables or endpoint. If private route tables lack a default route, the foundation normally rejects them. Explicit `create_private_nat_egress=true` plus `nat_public_subnet_id` creates an owned EIP/NAT and missing private default routes. The public subnet must route through an attached VPC IGW. A single NAT is an evaluation cost/availability tradeoff: cross-AZ traffic can cost more, and an AZ/NAT failure affects all three AZs. Foreign default routes are never overwritten or silently adopted. A route conflict can fail **after** NAT/EIP creation; inspect state and AWS before retrying or cleaning up. Do not turn this flag off while workloads depend on the NAT.

## Choose permissions, deployment and identities separately

| Permission mode | Instance resource owner | When to use it |
| --- | --- | --- |
| Default Permissions (`managed=true`) | Console can manage Data buckets, per-Instance cloud roles and private DNS, or use explicitly supplied existing resources | This example chooses automatic management; permits managed resource lifecycle and discovery |
| EC2 Mode Minimal Permissions | Customer supplies the required resources and grants the exported EC2 permission set | Customer-prepared EC2/ASG deployments; follow that mode's resource contract |
| EKS Mode Minimal Permissions | Customer pre-creates the Data bucket, data-plane role/identity, DNS and required namespace/KSA prerequisites, then grants the exported K8S permission set | Customer-prepared EKS deployments; adapt the Instance inputs as described below |

EKS Minimal also requires changing the Instance configuration to supply the customer-provided resource fields (`data_buckets`, `instance_role`, `dns_zone`, and namespace/KSA where required). Merely changing Console policy while retaining this managed root's omitted fields does not prepare those resources. Start from the [existing EKS example](../eks-existing/README.md) and the [Instance provider schema](https://registry.terraform.io/providers/automq/automq/0.4.8/docs/resources/kafka_instance), then verify the selected permission mode's exported policy and resource prerequisites in System Initialization.

| Independent choice | Supported forms and the selected path |
| --- | --- |
| Console deployment | VM/Docker or Helm; this example uses Helm on system nodes |
| Instance deployment | IAAS (EC2/ASG) or K8S; this example uses K8S |
| AWS Pod credentials | IRSA or EKS Pod Identity are different mechanisms; this example and the current managed data-plane path use IRSA. Pod Identity requires separate compatibility verification |
| Kubernetes API authorization | IAM principal + EKS Access Entry, or in-cluster KSA + RBAC; Console uses KSA + a binding to the existing `cluster-admin` role. The deployer uses its own Access Entry |

Pod identity isolates credentials; it does not itself reduce IAM actions or resources. Default Permissions and Kubernetes `cluster-admin` remain broad evaluation permissions. Some discovery/create APIs require wildcard resources; review the actual foundation policies. Nodes receive worker/ECR foundation policies, with no AutoMQ S3/DNS/IAM/WAL privileges. CNI, EBS CSI, LB Controller, Autoscaler, Console and each managed Instance use distinct Pod roles. Node IMDS requires v2 with hop limit 1 to restrict ordinary Pod access; hostNetwork/infrastructure Pods require separate review.

The current Azure new-AKS example still runs Console on a VM with UAMI and kubeconfig, and GCP's Kubernetes example pairs GKE with a VM Console using GSA/gcloud credentials. Their data-plane Pods use Workload Identity (KSA → Azure UAMI or Google GSA), independently of those VM Console identities. Their K8S data plane does not establish this AWS Console ServiceAccount path as an already shared deployment model.

## Shortest deployment path

Run commands from this directory. Each directory is an independent Terraform root and state owner. Adjacent local state is the default handoff; the state path inputs can be overridden. For team use, adapt the roots to a controlled remote backend and matching remote-state access. State access grants access to the full source state, even if outputs contain no CONFIG.

CONFIG, API secrets and Kafka passwords must not go into Git or command arguments. Terraform state and saved plans can contain plaintext CONFIG and Kafka passwords despite `sensitive` display redaction. Use a private directory (`umask 077`), encrypted storage, restricted backend access and protected backups. Kubernetes Secret encryption and access need the same care. Keep shell tracing and `TF_LOG` disabled; do not publish plans, state, raw CONFIG or Secret manifests.

```bash
umask 077
export AWS_PROFILE=your-profile
aws sts get-caller-identity
# Bash: read the complete CONFIG without terminal echo or a history entry.
read -r -s -p 'CONFIG: ' TF_VAR_automq_config; printf '\n'
export TF_VAR_automq_config
cp infrastructure/terraform.tfvars.example infrastructure/terraform.tfvars
```

Edit the non-secret infrastructure inputs. Confirm the fresh-Environment/CONFIG and Ops bucket `HeadBucket` absence checks described above before running the plan. Use discovered VPC/subnet/endpoint IDs and the intended deployer IAM role; choose existing egress or explicitly opt in to owned NAT. Review quota, private API reachability, capacity, tags and the plan before creation.

```bash
terraform -chdir=infrastructure init
terraform -chdir=infrastructure plan -out=foundation.tfplan
terraform -chdir=infrastructure apply foundation.tfplan
terraform -chdir=infrastructure output
```

Expected result: EKS and all four foundation add-ons are active, three AZ-specific business groups have initial capacity, and outputs identify the exact cluster, namespace, KSA, role and scheduling contract. Resolved add-on versions are output for reproducibility. The foundation owns no unused Instance Data bucket, Instance role or DNS zone.

```bash
cp console/terraform.tfvars.example console/terraform.tfvars
# Set console_image to the compatible, provenance-verified image.
terraform -chdir=console init
terraform -chdir=console plan -out=console.tfplan
terraform -chdir=console apply console.tfplan
python3 scripts/kubectl.py get nodes -L automq.io/pool,topology.kubernetes.io/zone
python3 scripts/kubectl.py -n automq-console get pods,pvc,service
python3 scripts/kubectl.py -n automq-console port-forward --address 127.0.0.1 service/automq-console-web-loadbalancer 8080:80
```

If you changed the foundation namespace, substitute its `console_namespace` output in kubectl commands. The wrapper creates a temporary cluster-specific kubeconfig with AWS exec authentication and uses the current profile; it does not use your current-context or store token/key values. It accepts normal kubectl arguments. The wrapper uses the default current-profile path; an alternate deployer role must be assumed before invoking it.

Open `http://127.0.0.1:8080` locally. Sign in with `admin/admin`, change the password, then complete any initialization prompts for **Default Permissions**. The AWS production CONFIG path automatically creates the environment and initializes system configuration; do not fill legacy customer-provided default Data buckets or Instance profiles. The Chart explicitly supplies `DEPLOY_TYPE=K8S`, VPC and account scope; Region comes from CONFIG and the EKS IRSA-injected AWS Region environment. Confirm the same EKS cluster and the `automq.io/pool=automq` selector plus `dedicated=automq:NoSchedule` toleration. Recreating the Pod with the same PVC must preserve the changed password. Create a Console **Service Account** with the required Instance and Kafka management permissions, then create its access keys. This is an AutoMQ management identity, separate from AWS credentials, the Kubernetes KSA, and the Kafka user. The example never generates or outputs a bootstrap API key.

In another Bash terminal, retain the port-forward and supply the management API endpoint and keys shown by the initialized Console:

```bash
export AUTOMQ_BYOC_ENDPOINT=http://127.0.0.1:8080
read -r -s -p 'AutoMQ access key: ' AUTOMQ_BYOC_ACCESS_KEY; printf '\n'
read -r -s -p 'AutoMQ secret key: ' AUTOMQ_BYOC_SECRET_KEY; printf '\n'
export AUTOMQ_BYOC_ACCESS_KEY AUTOMQ_BYOC_SECRET_KEY
cp automq-example/instance/terraform.tfvars.example automq-example/instance/terraform.tfvars
# Select an available data-plane version; the sample value is not a compatibility guarantee.
terraform -chdir=automq-example/instance init
terraform -chdir=automq-example/instance plan -out=instance.tfplan
terraform -chdir=automq-example/instance apply instance.tfplan
terraform -chdir=automq-example/instance output endpoints
```

The Instance takes the environment, cluster **name**, three private NLB subnets/AZs and scheduling values from foundation state. The `schedule_spec` serializes each selector key as an `In` match expression under required node affinity, plus the tolerations; the product converter accepts only `affinity` and `tolerations` at the top level. It uses three `m7g.xlarge` nodes, UsageBased pricing, S3WAL and SASL_PLAINTEXT. Data bucket, IAM role, DNS, namespace and KSA are omitted so CMP manages them. Keep Console ALB subnet choices separate from these private Kafka NLB subnets.

On the private Kafka client, install `confluent-kafka` in a virtual environment. Run the smoke root from a machine that can reach the management API, and run the Kafka script where broker DNS/routing works. Supply the same dedicated Kafka password to both processes through their environment.

```bash
read -r -s -p 'Dedicated Kafka password (16+ characters): ' TF_VAR_kafka_password; printf '\n'
export TF_VAR_kafka_password
terraform -chdir=automq-example/smoke init
terraform -chdir=automq-example/smoke apply
# Use the Instance SASL_PLAINTEXT bootstrap endpoint, without a protocol prefix.
export KAFKA_BOOTSTRAP_SERVERS=private-bootstrap-host:9092
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install confluent-kafka
python3 scripts/kafka-smoke.py
```

The root creates one single-partition topic, a dedicated Kafka user, a topic ACL and a prefix-scoped consumer-group ACL. The script records the starting offset, writes a unique marker with idempotent production, and requires exactly one record with matching key and bytes. It exits nonzero on delivery, content, count, authentication or timeout failure. The expected result is `PASS: produced and consumed exactly one matching record`. A ready Pod or Instance status alone does not satisfy this check. SASL_PLAINTEXT is limited to this controlled private evaluation network; it does not encrypt traffic.

## Optional Console ALB after initialization

Chart 8.3.28 has no generic ingress annotations/source-CIDR input. This root therefore keeps its ingress disabled. After changing the initial password, create a **separate, explicitly owned Ingress** targeting the `automq-console-web-loadbalancer` ClusterIP service (port 80), using `ingressClassName: alb`. Set `alb.ingress.kubernetes.io/target-type: ip`, `scheme` (prefer internal), exact **Console ALB** `subnets`, HTTPS-only `listen-ports: '[{"HTTPS":443}]'`, an ACM `certificate-arn` in the same Region, and `inbound-cidrs` with your real approved client ranges. Do not use `0.0.0.0/0`. Use the [controller annotation reference](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.13/guide/ingress/annotations/) to prepare and review the manifest before applying it.

With controller-managed frontend security groups, `inbound-cidrs` installs source restrictions. If you specify `security-groups`, configure the actual SG ingress rules yourself: the annotation alone does not restrict those groups. Verify the resulting ALB listeners, scheme, subnets, SG rules and effective denied-source behavior before using its endpoint. Record the manifest and cloud IDs for cleanup. This is an additional user-managed deployment step, not a claim that the pinned Chart enforces an unsupported value.

## Verify and recover

| Layer | Evidence to collect | Failure checks |
| --- | --- | --- |
| Foundation | Actual caller, EKS/add-on status, per-AZ nodes, outbound connectivity | Private API routes/SGs, S3 endpoint policy, NAT routes, quotas, arm64 image availability |
| Console | Ready Pod, bound gp3 PVC, changed login survives Pod replacement | CSI Pod IRSA, AZ attachment/scheduling, CONFIG match, compatible image and subscription |
| Kubernetes authorization | `auth can-i` for exact Console KSA and actual in-Pod API operations | KSA token mounting, cluster-admin binding, same-cluster discovery; do not substitute IAM kubeconfig |
| AWS identity | Actual STS caller from a controlled Pod using each intended KSA; exact trust `aud` and `sub` | A token for a different KSA must fail `AssumeRoleWithWebIdentity`; inspect canonical managed-role ownership and policies |
| Instance | Three AZs, private NLB subnet placement, managed Data bucket/role/DNS ownership, business selector/taint | CMP events, AWS policy errors, controller logs, ECR and DNS reachability |
| Kafka / scaling | Unique marker PASS; workload-driven scale-out event followed by bounded return | ACLs, all advertised endpoints, ASG discovery tags, max nodes and business scheduling |

Inspect actual Node role attachments and inline policies: no AutoMQ business actions may be added as a workaround. Pod annotations alone do not prove caller identity or denied cross-KSA access. The default S3WAL runtime role should retain Data/Ops S3 permissions and omit EC2 volume actions; the independent CSI role owns metadata disk operations. Keep hostNetwork and infrastructure Pod credential exceptions visible in runtime evidence.

When a create operation times out or returns an uncertain result, query the Console/AWS for the exact name and ownership first. If creation succeeded but Terraform has no ID, use the provider's documented import form after confirming the exact environment/Instance identity; inspect `terraform state list` and the next plan. If import is unavailable, explicitly clean the confirmed owned partial resource before retrying. Never blindly repeat create or guess an ID. Do not repair foreign/customer IAM trust or add ownership tags to make a resource appear managed. Save redacted diagnostics, not secrets.

## Cleanup by owner

Review data retention and ownership before destruction. Keep Console, controllers, CSI and the network available until their dependent resources finish deleting.

1. Destroy `automq-example/smoke`, then `automq-example/instance` while the Console API and keys still work. Verify CMP removes its owned LoadBalancer Services/NLBs, pods/PVCs, IAM roles/policies, private DNS and Data bucket according to the chosen product data-retention behavior. The AWS production default `deleteManagedBucketWhenDeleteInstance=false` retains the managed Data bucket: record its exact ownership/ID before deleting the Instance, then back up or explicitly empty/delete that owned bucket only when intended. Check for partial-create resources by exact tags/IDs. Before uninstalling AWS Load Balancer Controller, wait for each Instance NLB, its target groups, requester-managed ENIs and per-Service frontend security group to disappear. Inventory all three subnet/AZ ENIs for the three-AZ NLB; deleting the Service is only the start of cloud cleanup. Frontend security groups carry `service.k8s.aws/stack=<namespace>/<service>`. After the Instance and its dynamic resources are confirmed deleted, revoke the temporary AutoMQ management Service Account/access keys while the Console API still works, before destroying Console.
2. Delete any separately created Console ALB Ingress and wait for its LB/target groups/ENIs/SGs to disappear. After the last load-balanced Service in this cluster is deleted, inspect the controller's cluster-shared backend security group (`elbv2.k8s.aws/cluster=<exact-EKS-name>`) and references from Node security-group rules. This group belongs to the cluster, not an individual Instance. Do not delete it as an Instance-private frontend group. If it remains, explicitly clean it only after confirming exact cluster ownership and no remaining LB, ENI or security-group references; otherwise record the retained group and its references. Keep LB Controller installed until these dependent deletions complete.
3. Record Console PVC/PV and EBS volume IDs. Back up data if required. Destroy `console`; its namespace, CONFIG Secret, KSA and binding are owned by that root. The `Retain` storage class deliberately retains the PV/EBS data after PVC deletion; explicitly delete only the confirmed owned PV/EBS volume when the data can be discarded. This prevents accidental loss but can leave charges.
4. Check remaining NLB/ALB/ENI/frontend and shared backend SGs, Node SG references, PVC/PV/EBS, managed IAM, DNS and bucket resources. Destroy `infrastructure` only after dependent cleanup. The Ops bucket is not force-destroyed: inventory/back up its data, then explicitly empty only that owned bucket if deletion is intended. If it stays non-empty, destruction correctly fails. Review owned NAT/EIP/default routes; existing customer VPC/subnet/route-table/endpoint resources stay customer-owned.
5. Destroy optional `network-example` last. Unset secret environment variables and remove protected local plans/state according to retention requirements. Retained EBS, non-empty buckets, LBs and NAT/EIP can continue billing; verify the final inventory in AWS.

## Local validation and CI

The [independent EKS workflow](../../../../.github/workflows/terraform-validate.yml) matrix runs `init -backend=false`, `validate` and Terraform mock/negative tests for every root. Any command failure fails the job. Chart checks pull and render the actual 8.3.28 OCI Chart, then assert external KSA/Secret references, lowercase `config`, PVC, system scheduling and ClusterIP. Script/document checks compile Python without writing bytecode, validate local links and detect unfinished placeholders.

```bash
terraform -chdir=console test
terraform -chdir=automq-example/instance test
terraform -chdir=automq-example/smoke test
python3 scripts/check-chart.py
python3 scripts/check-static.py
```

These checks do not create cloud resources. Cloud identity, persistence, three-AZ placement, private Kafka traffic, scaling, cleanup and reconstruction require a separate live acceptance run with the compatible image. The pinned Autoscaler image matches EKS 1.36 explicitly; chart 9.59.0's default image is 1.35 and is overridden. See the [upstream 1.36 release](https://github.com/kubernetes/autoscaler/releases/tag/cluster-autoscaler-1.36.0).
