# Operations and troubleshooting

Use this page to check health and authorization, scale the Instance and EKS capacity, expose Console through HTTPS, recover a partial failure or remove the environment. The [deployment guide](../README.md) contains the standard installation path.

## Check deployment health

Run commands from the example directory, using the AWS profile/role authorized for the new cluster. Activate the Python environment prepared in the deployment guide. Substitute your namespace if you changed `console_namespace`.

```bash
. .venv/bin/activate
aws sts get-caller-identity
python3 scripts/kubectl.py get nodes -L automq.io/pool,topology.kubernetes.io/zone
python3 scripts/kubectl.py -n automq-console get pods,pvc,service
python3 scripts/kubectl.py -n kube-system get pods
```

| Symptom | Check | Action |
| --- | --- | --- |
| Terraform or kubectl cannot reach EKS | Private API routing/VPN, public API allowlist and effective workstation source IP | Restore the configured API path. A public EKS endpoint does not provide private Kafka connectivity |
| Kubernetes reports unauthorized | Current AWS profile/role versus `deployer_role_arn`, deployer Access Entry | Use the authorized deployer role. Console's runtime role is a separate identity |
| Nodes do not become ready or images do not pull | Outbound routes/NAT, DNS, registry access, instance quota and image architecture | Restore AWS API/registry access; system nodes are x86, business nodes are ARM |
| Console PVC stays pending | EBS CSI controller and IRSA, StorageClass, available capacity and AZ scheduling | Inspect PVC events and CSI logs before changing storage |
| Console cannot initialize | Complete CONFIG, matching Environment/Region/Ops bucket, subscription and released AWS Console image | Confirm the installation values and selected release with AutoMQ |
| Instance creation fails | Console events, data-plane version/specification availability, IAM errors, selected EKS cluster and three-AZ capacity | Fix the reported precondition and recover the existing operation before retrying |
| Kafka bootstrap connects but produce/consume fails | Private DNS and routing to **all advertised broker endpoints**, SASL credentials and Topic/Consumer group ACLs | Use the exact returned endpoint/port and the dedicated Kafka password, not management keys. For clients in another VPC, review [cross-VPC access](https://docs.automq.com/automq-cloud/getting-started/install-byoc-environment/aws/prepare-vpc#configure-cross-vpc-access) |
| Pending Pods do not trigger capacity | Autoscaler Pod/logs, node-pool maximums, business affinity/taint compatibility and AWS quota | Check the scheduling cause and available pool capacity; node scaling does not change Instance node count |

Collect only the diagnostics relevant to the failed component:

```bash
python3 scripts/kubectl.py -n automq-console get events --sort-by=.lastTimestamp
python3 scripts/kubectl.py -n kube-system logs deployment/aws-load-balancer-controller --tail=100
python3 scripts/kubectl.py -n kube-system get deployments
```

If a Deployment has a different name, list the Deployments in `kube-system` first and use that exact name. Remove credentials, Secret values and sensitive request content before sharing diagnostics.

## Check runtime authorization

Console obtains its IAM role through its Pod ServiceAccount and IRSA. A `STANDARD` EKS Access Entry associates that role with cluster-scoped `AmazonEKSClusterAdminPolicy`, allowing Console to manage Kubernetes resources. The deployer has a separate Access Entry. Each Instance, CNI, EBS CSI, LB Controller and Cluster Autoscaler uses its own Pod role for AWS access.

When an AWS request is denied, inspect the intended role's trust and permissions, the Pod ServiceAccount and the actual caller. For roles prepared by these Terraform roots, verify that IRSA trust matches the EKS OIDC issuer, audience `sts.amazonaws.com` and intended namespace/ServiceAccount. Check Console's EKS Access Entry and associated access policy separately from S3/IAM permissions. Inspect actual Node role attachments as well: AutoMQ S3, DNS, IAM management or WAL permissions must not be added to Nodes as a workaround. Pod annotations alone do not establish the caller used for a request.

For the AWS role-to-ServiceAccount requirements, see the official [Instance IAM role and ServiceAccount guide](https://docs.automq.com/automq-cloud/deploy-automq-on-kubernetes/deploy-to-aws-eks#step-5-prepare-the-automq-workload-iam-role-and-serviceaccount). Use it to review the role-to-ServiceAccount relationship while keeping this example's IRSA configuration. The Console and infrastructure components retain their separate roles.

For S3WAL, Instance permissions cover its Data and Ops S3 resources; metadata disk operations use the EBS CSI identity. Ordinary Pods are restricted from Node credentials with IMDSv2/hop limit 1. Review hostNetwork and infrastructure Pods separately.

## Scale the Instance and managed node groups

Use the deployment terminal from [Create the Kafka Instance](../README.md#4-create-the-kafka-instance), with the same AWS profile and `AUTOMQ_BYOC_ENDPOINT`, `AUTOMQ_BYOC_ACCESS_KEY` and `AUTOMQ_BYOC_SECRET_KEY` available. Keep the Console port-forward running. Confirm the Instance is available before submitting another change.

There are two sizes to observe:

| Size | Controlled by | What changes it |
| --- | --- | --- |
| AutoMQ node count | Console management API, requested by the Instance Terraform root | `instance_node_count` |
| EC2 capacity in each managed node group | Cluster Autoscaler, bounded by the foundation minimum/maximum | Pods that cannot be scheduled, then nodes that are no longer needed |

The default is three AutoMQ nodes and one business EC2 node in each AZ. The following commands temporarily override `instance_node_count` to demonstrate **three → six → three**. For a lasting size change, save the desired count in `automq-example/instance/terraform.tfvars` so later plans keep the same intent.

### Scale out to six AutoMQ nodes

Check that `automq_max_nodes_per_az` permits at least two business EC2 nodes per AZ and that the account has the required EC2 quota. Review the Instance plan, then apply it:

```bash
terraform -chdir=automq-example/instance plan \
  -var='instance_node_count=6' -out=scale-out.tfplan
terraform -chdir=automq-example/instance apply scale-out.tfplan
```

In another deployment terminal, observe the Pods and EC2-backed Kubernetes nodes:

```bash
AUTOMQ_INSTANCE_ID="$(terraform -chdir=automq-example/instance output -raw instance_id)"
python3 scripts/kubectl.py -n "$AUTOMQ_INSTANCE_ID" get pods -o wide
python3 scripts/kubectl.py get nodes \
  -L automq.io/pool,topology.kubernetes.io/zone,node.kubernetes.io/instance-type
python3 scripts/kubectl.py -n kube-system get deployments
```

Use the actual Cluster Autoscaler Deployment name from the last command to read its logs. Look for unschedulable Pods, a scale-up decision and new Nodes becoming `Ready`. With the default node sizes and scheduling, the extra AutoMQ Pods require more business-node capacity. Keep the system pool separate from this count.

**Expected result:** the Instance returns to an available state with six AutoMQ Pods `Ready`, distributed across all three AZs, and sufficient business EC2 nodes to run them. On the [private Kafka client](../README.md#6-produce-and-consume-from-a-private-client), run `python3 kafka-smoke.py` again with the same endpoint and Kafka credentials. Review client errors while the size change is in progress.

### Scale back to three AutoMQ nodes

After the six-node Instance and Kafka check succeed, request three nodes:

```bash
terraform -chdir=automq-example/instance plan \
  -var='instance_node_count=3' -out=scale-in.tfplan
terraform -chdir=automq-example/instance apply scale-in.tfplan
```

**Expected result:** the Instance returns to an available state with three AutoMQ Pods `Ready` across the three AZs. Run the private Kafka check again. Cluster Autoscaler can remove the unneeded EC2 nodes after its scale-down delay and safety checks; continue observing the business pools until they return to the initial capacity of one node per AZ. Instance completion and EC2 node removal are separate events.

Cluster Autoscaler owns the desired capacity of the three AutoMQ business pools. Terraform keeps the system pool at a desired capacity of two when you apply the foundation; Autoscaler can adjust it temporarily within its configured limits. Changing an Instance specification affects the business pools, not the system-pool target.

In this default S3WAL example, the three controller Pods and their three metadata PVCs remain in place. Scaling changes the number of broker Pods and the EC2 capacity they need. Brokers use `emptyDir`, so this procedure creates no additional broker PVCs. For other storage configurations, check the actual StatefulSet volume-retention policy before planning storage cleanup.

If Pods remain Pending, inspect their scheduling events, the node-group limit, AutoMQ affinity/taints, EC2 quota and Autoscaler logs. If the Instance remains `Updating` while all Pods are ready and there is no scheduling backlog, inspect the Console task/logs and its EKS Access Entry rather than changing EC2 capacity.

## Recover an uncertain create operation

A timeout can occur after the remote resource was created. Before repeating a create:

1. Check Console and AWS for the exact Environment, Instance name and resource ownership.
2. Check `terraform state list` in the affected root and review the next plan.
3. If the resource exists but state has no ID, confirm its exact identity and use the provider's documented import form. If import is unavailable, explicitly remove only the confirmed owned partial resource before retrying.

Do not guess an Instance ID or add ownership tags to adopt an unrelated role. Retain a redacted error and request ID when asking AutoMQ for help.

## Access Console from a remote deployment host

When Terraform runs on a remote VPC-connected host, the Console port-forward listens on that host's `127.0.0.1`, not your laptop. Keep the `scripts/kubectl.py ... port-forward --address 127.0.0.1` command running on the deployment host.

Use an existing approved SSH path to that host. In a terminal **on your laptop**, create a local tunnel:

```bash
read -r -p 'Deployment SSH target (user@host): ' DEPLOYMENT_HOST
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8080:127.0.0.1:8080 "$DEPLOYMENT_HOST"
```

Keep this SSH terminal open and visit `http://127.0.0.1:8080` in your laptop's browser. If local port 8080 is occupied, change the first port in the `-L` mapping and use that local port in the browser URL. The tunnel does not open a public Console endpoint.

Run the Instance and Kafka-management Terraform commands in another terminal on the original deployment host; their `AUTOMQ_BYOC_ENDPOINT=http://127.0.0.1:8080` still refers to that host's port-forward. Keep Terraform state, CONFIG and management keys there. The laptop only needs its browser and SSH access. Kafka application access remains a separate private-network path.

## Optional Console HTTPS endpoint

The default localhost port-forward keeps Console access on the deployment machine. For a persistent endpoint, first change the initial Console password, then create a separately managed Ingress targeting Service `automq-console-web-loadbalancer`, port `80`, in the Console namespace. Use `ingressClassName: alb` and the existing AWS Load Balancer Controller.

| Ingress setting | Required choice |
| --- | --- |
| `alb.ingress.kubernetes.io/target-type` | `ip` |
| `alb.ingress.kubernetes.io/scheme` | Prefer `internal`; choose the scheme to match your intended access network |
| `alb.ingress.kubernetes.io/subnets` | Exact **Console ALB** subnet IDs suitable for that scheme; separate from the Kafka NLB subnet selection |
| `alb.ingress.kubernetes.io/listen-ports` | `[{"HTTPS":443}]` |
| `alb.ingress.kubernetes.io/certificate-arn` | ACM certificate ARN in the same Region |
| `alb.ingress.kubernetes.io/inbound-cidrs` | Approved client source ranges, never `0.0.0.0/0` |

The pinned Console Chart has no generic source-CIDR/annotation input, so keep its built-in ingress disabled and manage this Ingress separately. With controller-managed frontend security groups, `inbound-cidrs` installs source restrictions. If you specify `security-groups`, configure their actual ingress rules yourself; the CIDR annotation does not restrict those custom groups.

Review the [controller annotation reference](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.13/guide/ingress/annotations/). Before using the endpoint, verify the actual listeners, scheme, subnets, SG rules and denied-source behavior. Record the Ingress and cloud resource IDs so they can be removed before the controller is uninstalled.

## Cleanup checklist

Deleting the environment stops Kafka traffic. Decide which data to preserve before starting, and keep Console, its management API credentials, controllers and network available until dependent deletion finishes.

### 1. Record resource ownership and retained data

Record the Instance ID, Data bucket and its ownership tags, private DNS zone, load balancers and metadata volumes. Confirm the Data bucket tags include `automqVendor=automq` and `automqInstanceID` equal to that Instance ID. Record Console's PVC/PV/EBS volume IDs before deleting the namespace:

```bash
terraform -chdir=automq-example/instance output instance_id
python3 scripts/kubectl.py -n automq-console get pvc -o wide
```

Inspect the exact Console PV and its CSI volume handle to identify the EBS volume. Confirm names, IDs and current tags in AWS; do not select resources for deletion only by a name prefix.

| Data/resource | Default behavior | Your cleanup decision |
| --- | --- | --- |
| Instance Data bucket | Retained by the AWS product default `deleteManagedBucketWhenDeleteInstance=false` | Back up/retain, or explicitly empty/delete only the confirmed Instance-owned bucket |
| Instance metadata PVC/EBS | Deleted through Instance/Kubernetes cleanup | Wait for PVC/PV/EBS removal while CSI is still running |
| Console PV/EBS | `Retain` storage class preserves data after PVC deletion | Back up/retain, or delete the exact released PV and detached EBS volume after Console stops |
| Ops bucket | Foundation uses `force_destroy=false` | Back up and explicitly empty only the owned bucket before foundation destruction |
| EKS KMS key | AWS scheduled-deletion window | Record its pending-deletion state/date; it is not physically deleted immediately |

Retained disks, buckets, load balancers and NAT gateways can continue incurring charges. Preserve the relevant application data before deleting a bucket or disk.

### 2. Delete Kafka verification and the Instance

Use the management endpoint/keys from the deployment guide and keep the Console port-forward active:

```bash
terraform -chdir=automq-example/smoke destroy
terraform -chdir=automq-example/instance destroy
```

Wait for Console to finish deleting the Instance. Confirm its namespace/workloads, managed IAM role/policies, private DNS and metadata disks are removed. Check the selected data-retention behavior separately; a retained Data bucket is not an Instance deletion failure.

Before removing the AWS Load Balancer Controller, confirm every Instance NLB, its target groups, requester-managed ENIs in all three AZs and per-Service frontend SG are gone. A deleted Kubernetes Service can still have AWS cleanup in progress. Frontend SGs carry `service.k8s.aws/stack=<namespace>/<service>`.

The controller can also create a **cluster-shared backend SG** carrying the exact cluster name in `elbv2.k8s.aws/cluster` and `elbv2.k8s.aws/resource=backend-sg`. It belongs to the cluster, not one Instance. If it remains after the last load-balanced Service is gone, check its exact cluster ownership and all ENI/Node-SG references. Remove it only after no dependent resources or references remain; otherwise retain and investigate it.

Revoke the temporary AutoMQ management Service Account/access keys **now**, while Console is still available and after all Instance management is complete.

### 3. Remove optional ingress, then Console

If you added a separate Console ALB Ingress, delete that Ingress first and wait for its ALB/target groups/ENIs/SGs to disappear. Keep the LB Controller until that cleanup finishes.

Use the same complete CONFIG as deployment, obtained from your [AutoMQ Environment installation script](../README.md#get-your-automq-environment-configuration). In the terminal used for cleanup, read it again without echo if it is not already set:

```bash
umask 077
read -r -s -p 'AutoMQ CONFIG: ' TF_VAR_automq_config; printf '\n'
export TF_VAR_automq_config
terraform -chdir=console destroy
```

After the Console Pod and namespace are gone, inspect the recorded retained PV/EBS. Before deleting data, verify the PV's claim UID and CSI volume ID, `Retain` policy and `Released` state; verify the EBS volume's tags/creation identity and that it is detached/available. Delete only those exact owned resources when you intend to discard their data. Preserve Kubernetes built-in roles and Access Entries owned by other administrators or services.

### 4. Remove the foundation and optional network

Check that dependent load balancers, ENIs, workload volumes, Instance IAM/DNS and separately managed Ingress resources are gone. Back up the Ops bucket, then explicitly empty that owned bucket if you intend to delete the environment. A non-empty Ops bucket correctly blocks Terraform deletion.

```bash
terraform -chdir=infrastructure destroy
```

This removes the new EKS, node groups, foundation roles, logs and other managed foundation resources. It also removes the NAT/EIP/default routes only if this foundation created them. The existing VPC, subnets, route tables and S3 Endpoint are preserved.

If you used `network-example/`, destroy it last, after confirming it has no remaining dependents:

```bash
terraform -chdir=network-example destroy
```

### 5. Check the final AWS inventory

Confirm no unwanted EKS, EC2/ASG, EBS, LB/TG/ENI/SG, IAM, DNS, bucket, NAT/EIP or log resources remain for this deployment. Record intentional retained data and pending KMS deletion. Keep customer-owned networks and unrelated resources.

Unset `TF_VAR_automq_config`, `AUTOMQ_BYOC_ACCESS_KEY`, `AUTOMQ_BYOC_SECRET_KEY` and `TF_VAR_kafka_password` in each shell. Stop the port-forward and remove protected local state/plans according to your retention policy.
