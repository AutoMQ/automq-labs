# SSM Operations Access for AWS EC2 BYOC

Use this procedure when you want authorized AutoMQ operators to open a
Session Manager shell on the Console EC2 host. The native Session Manager shell
does not require an SSH key, `sshd`, or inbound TCP 22. SSH tunneled through
Session Manager is a different mode: it still requires `sshd` and SSH
credentials, and Session Manager cannot log the commands inside that tunnel.
[AWS explains the distinction](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html).

The Console instance role lets the **agent on the host** connect to AWS.
The separate operator role below lets an **AutoMQ person** start a session.
Neither role grants the other role's permissions.

## 1. Verify that the Console host is managed by SSM

The Console root already attaches
[`AmazonSSMManagedInstanceCore`](../automq-console/iam.tf) to its existing Console
EC2 role and assigns that role through an instance profile. Keep this
attachment if you customize the root; an EC2 instance cannot use a second
instance profile alongside the Console profile. The example selects the
standard Amazon Linux 2023 AMI through the public SSM parameter. Verify that
SSM Agent is installed and running on the actual instance. It uses the instance
role to register with Systems Manager and establish its message channels.
[AWS documents the instance permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html).

From `automq-console`, get the target instance ID:

```bash
terraform output -raw console_instance_id
```

Check the instance in **AWS Systems Manager > Fleet Manager > Managed nodes**.
Its ping status must be `Online`. You can also query it with the AWS CLI:

```bash
aws ssm describe-instance-information --region <REGION> \
  --filters Key=InstanceIds,Values=<CONSOLE_INSTANCE_ID>
```

The Console security group has no SSH ingress. The host must reach regional
`ssm` and `ssmmessages` endpoints over outbound HTTPS 443. This example's
public Console subnet and outbound security group rule provide an internet
path; a private deployment needs NAT or suitable interface VPC endpoints,
private DNS, and endpoint security group access. Older agent/Region
combinations can also need `ec2messages`.
[AWS lists the network requirements](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html).

If you replace the AMI with one that lacks SSM Agent, install and start it in
the AMI or instance user data before closing other management access:

```bash
sudo dnf install -y amazon-ssm-agent
sudo systemctl enable --now amazon-ssm-agent
```

If the host is not `Online`, check the instance profile, Agent service and
logs, Region, DNS, and outbound 443 before granting operator access. On the
host, check `systemctl status amazon-ssm-agent` and
`/var/log/amazon/ssm/amazon-ssm-agent.log`.

## 2. Deploy the customer-owned operator role

Keep this Terraform root separate from `automq-console` and `automq-cluster`.
It takes the existing AWS account, Region, instance IDs, and IAM role names as
inputs. It does not read either root's Terraform state or modify their source.

Ask AutoMQ for the specific IAM Role ARN used by its operators and a unique
External ID for your customer account. From `automq-console`, obtain the
Console instance and data-plane role names after applying that root:

The [AWS Ops authorization guide](https://docs.automq.com/zh/automq-cloud/manage-environments/manage-environment-ops-authing/set-ops-authing-from-aws)
lists an AutoMQ AWS account ID for **S3 Ops Bucket access**. It does not
provide an External ID or identify the IAM Role for this SSM connection. Do
not substitute that account ID for either value.

```bash
terraform output -raw console_instance_id
```

```bash
terraform output -raw cluster_role_name
```

The Console root already attaches `AmazonSSMManagedInstanceCore` to its own
instance role. To let broker EC2 hosts register with SSM, put the
`cluster_role_name` value in `additional_instance_role_names`. This root will
attach the same AWS managed policy to that existing node role. Leave the list
empty if you only need Console access. Do not add the Console role to this
list, because its attachment is already managed by the Console Terraform root.

In this `ssm-operations-access` directory, create a local `terraform.tfvars`:

```hcl
aws_region                     = "<REGION>"
operator_role_name             = "automq-ssm-operator-<ENVIRONMENT>"
automq_principal_arn           = "arn:aws:iam::<AUTOMQ_ACCOUNT_ID>:role/<AUTOMQ_OPERATOR_ROLE>"
external_id                   = "<CUSTOMER_SPECIFIC_EXTERNAL_ID>"
target_instance_ids           = ["<CONSOLE_INSTANCE_ID>"]
additional_instance_role_names = ["<CLUSTER_ROLE_NAME>"]
```

Set `additional_instance_role_names = []` for Console-only access. Add broker
EC2 instance IDs to `target_instance_ids` only after you identify and approve
them. Updating the input and applying again updates the allowed instance ARNs.
Keep `terraform.tfvars` and Terraform state private; they contain the External
ID and the operator Role configuration. Confirm the AWS identity points to
your customer account, then apply this directory:

```bash
aws sts get-caller-identity
```

```bash
terraform init
```

```bash
terraform plan
```

```bash
terraform apply
```

```bash
terraform output -raw ssm_operator_role_arn
```

[`ssm-operator.tf`](ssm-operator.tf) creates a role that trusts only the named
AutoMQ IAM Principal with the supplied `sts:ExternalId`. AutoMQ must separately
allow that source Principal to assume the output role ARN. Verify that a
missing or incorrect External ID is rejected.
[AWS describes cross-account third-party access](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html).

The generated policy requires **both** an approved EC2 instance ID and the
case-sensitive `automqVendor=automq` tag on that instance. The Console root
sets this tag on its EC2 host. Check the actual tag on every broker EC2 host
before adding its ID; a tag on the IAM role or AutoMQ Instance alone does not
satisfy the SSM policy. The assumed operator role cannot create or delete the
access tag. Protect other identities that can set the tag, create tagged EC2
instances, or change this role's policies.
[AWS documents tag-based Session Manager access](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html).

The policy grants native Session Manager shell access. It does not grant
`ssm:SendCommand` or SSH-over-SSM access. Give AutoMQ the
`ssm_operator_role_arn`, AWS account ID, Region, and approved instance ID.
With short-lived assumed credentials, AWS CLI, and the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html),
operators confirm their identity and open a shell:

```bash
aws sts get-caller-identity --profile <ASSUMED_OPERATOR_PROFILE>
```

```bash
aws ssm start-session --profile <ASSUMED_OPERATOR_PROFILE> \
  --region <REGION> --target <CONSOLE_INSTANCE_ID>
```

Confirm the session opens on the expected host and that an unapproved or
untagged instance returns `AccessDenied`. The default Linux user, `ssm-user`,
normally has sudo privileges; treat this as privileged host access.

## 3. Review sessions and API activity

In the customer AWS account, configure **Systems Manager > Session Manager >
Preferences** to deliver native shell session content to a customer-owned
CloudWatch Logs log group or S3 bucket. Set retention and access controls for
that destination. Open the configured log group or bucket to review commands
from sessions created **after** logging was enabled.
[AWS explains session logging and its limitations](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html).

Use **CloudTrail > Event history** in the same Region to find `StartSession`
and `TerminateSession` API events and identify the assumed operator role,
target, and time. CloudTrail records API activity, not shell command content.
For a longer retention period or centralized audit, configure a CloudTrail
trail. SSH-over-SSM and port-forwarding tunnel content cannot be captured by
Session Manager session logging.
[AWS documents the CloudTrail events](https://docs.aws.amazon.com/systems-manager/latest/userguide/monitoring-cloudtrail-logs.html).

