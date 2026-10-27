# Configure SSM Operations Access for an AWS EC2 BYOC Environment

AWS Systems Manager (SSM) Session Manager provides an operations access path to your AutoMQ BYOC environment. When host troubleshooting is needed, authorized AutoMQ operators can access the Console or data plane EC2 instances you specify. You control the access scope, audit records, and revocation in your AWS account.

This guide uses a **native Session Manager shell**. The SSM Agent on each EC2 instance connects to AWS services, so operators do not need an SSH private key or inbound TCP port 22. SSH over an SSM tunnel works differently: it still requires `sshd` and SSH credentials, and Session Manager cannot log commands sent through the tunnel. [AWS: Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) · [AWS: SSH over SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html)

## How access works

1. You enable the SSM Agent on each target EC2 instance and allow outbound HTTPS 443 access to the regional SSM services.
2. You create an **SSM operations role** in your AWS account. It trusts only the specific AutoMQ IAM Role provided to you and requires the customer-specific External ID agreed with AutoMQ.
3. An authorized AutoMQ operator obtains temporary credentials through `sts:AssumeRole`, then calls `ssm:StartSession` for an EC2 instance you allow.
4. You can change the allowed instances or revoke the role at any time and inspect access records in your AWS account.

## Prepare the Console and data plane EC2 instances

### 1. Check and start the SSM Agent

The Console and every data plane EC2 instance you want to access must run the SSM Agent. This example uses an Amazon Linux 2023 AMI. First, check each target host for the Agent:

```bash
rpm -q amazon-ssm-agent
```

If the Agent is absent, install it. For another operating system, follow the [AWS installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/manually-install-ssm-agent-linux.html). See the [AWS preinstalled Agent list](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html) to check whether a standard AMI includes it.

```bash
sudo dnf install -y amazon-ssm-agent
```

Start the Agent and enable it at boot:

```bash
sudo systemctl enable --now amazon-ssm-agent
```

Confirm that the service is running:

```bash
sudo systemctl status amazon-ssm-agent
```

### 2. Grant the target hosts' instance profile roles SSM permissions

The SSM Agent uses the IAM Role in the host's existing instance profile to register with Systems Manager and establish a message channel. Attach the AWS managed policy `AmazonSSMManagedInstanceCore` to that role while retaining its application permissions. [AWS: instance permissions](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html)

In **AWS EC2 Console > Instances**, select the Console EC2 instance and open **Security > IAM Role** to see its actual role. The [Console Terraform example](../automq-console/iam.tf) already attaches `AmazonSSMManagedInstanceCore` to this role.

To access data plane hosts, find the target Instance's **IAM Role** on the **AutoMQ Console > Instance** page. This role is used by that Instance's Broker EC2 hosts. Use its role name in the following command:

```bash
aws iam attach-role-policy --role-name <BROKER_INSTANCE_ROLE_NAME> \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

Confirm that the policy is attached:

```bash
aws iam list-attached-role-policies --role-name <BROKER_INSTANCE_ROLE_NAME>
```

If you used another Console deployment template, inspect the Console EC2 instance's **IAM Role** and attach the same policy to that existing role if needed.

### 3. Check network access and registration

Each target EC2 instance needs outbound HTTPS 443 access to the `ssm` and `ssmmessages` services in its Region. Use your existing internet or NAT route, or create Interface VPC Endpoints with Private DNS and security group rules that allow access from the instances. Older Regions or Agent versions may also require `ec2messages`. [AWS: Systems Manager VPC Endpoints](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)

In **AWS Systems Manager > Fleet Manager > Managed nodes**, confirm that each target host is `Online`. You can also query a specific instance:

```bash
aws ssm describe-instance-information --region <REGION> \
  --filters Key=InstanceIds,Values=<INSTANCE_ID>
```

If a host is not `Online`, check the Agent service, instance profile, outbound network access, DNS, and `/var/log/amazon/ssm/amazon-ssm-agent.log`. [AWS: troubleshoot the SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-ssm-agent.html)

## Create the customer-side SSM operations role

The [Terraform example](ssm-operator.tf) in this directory creates a customer-side operations role. It allows sessions to EC2 instances in the specified Region and customer account that have the case-sensitive tag `automqVendor=automq`. This includes any other instances with that tag. It does not read or modify the Console or Cluster Terraform state.

Create a local `terraform.tfvars` in this directory and replace the placeholders with your values. AWS recommends a unique External ID for each customer when a third party serves multiple customers ([AWS guidance](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html)). Keep this file and the Terraform state in a controlled location because they contain the External ID.

```hcl
region          = "<REGION>"
automq_role_arn = "arn:aws:iam::<AUTOMQ_ACCOUNT_ID>:role/<AUTOMQ_OPERATOR_ROLE>"
external_id     = "<CUSTOMER_SPECIFIC_EXTERNAL_ID>"
```

The default role name is `automq-ssm-operator`. Set `role_name` if you need more than one operations role in the account. Verify your AWS identity in the customer account, then initialize, review, and apply the configuration:

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

Give AutoMQ the ARN of the resulting customer-side operations role:

```bash
terraform output -raw ssm_operator_role_arn
```

You can inspect the role's trust policy and session permissions with the AWS CLI:

```bash
aws iam get-role --role-name <ROLE_NAME>
```

```bash
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name ssm-operator
```

Also provide AutoMQ with your AWS account ID and Region. AutoMQ must allow its designated IAM Role to call `sts:AssumeRole` in its own account and pass the agreed External ID in the request.

## Review access boundaries and audit records

The customer-side role trusts only the AutoMQ IAM Role specified in `automq_role_arn` and requires the correct `sts:ExternalId`. Only people or processes permitted to use that AutoMQ Role can attempt to assume the customer-side role. AutoMQ manages access for its operators. The customer-side policy allows access to **every EC2 instance in the specified Region and customer account** that has the case-sensitive tag `automqVendor=automq`. Tagging only the role or the AutoMQ Instance does not satisfy this condition. The assumed role is explicitly denied permission to add or remove this access-boundary tag on EC2 instances. You should also restrict other identities from changing the tag or the operations role. If you need a narrower scope, add a customer-controlled EC2 tag condition to the policy before applying it. [AWS: instance, tag, Session document, and own-session policy examples](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html)

If you deployed the Console from this example, get its EC2 instance ID from the `automq-console` directory before checking its tag:

```bash
terraform output -raw console_instance_id
```

Check the tag on a target EC2 instance with the AWS CLI:

```bash
aws ec2 describe-tags --region <REGION> \
  --filters Name=resource-id,Values=<INSTANCE_ID> Name=key,Values=automqVendor
```

This configuration grants native Session Manager shell access, but not `ssm:SendCommand` or SSH over SSM. [AWS's sample Session Manager policies](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-quickstart.html) show `StartSession`, Session document, and session management permissions; some also grant `SendCommand`. Operators use temporary credentials and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) to access authorized hosts. The default Linux session user, `ssm-user`, usually has sudo access; treat these sessions as privileged host access.

AutoMQ operators can verify their temporary identity before starting a session:

```bash
aws sts get-caller-identity --profile <AUTOMQ_ASSUMED_ROLE_PROFILE>
```

```bash
aws ssm start-session --profile <AUTOMQ_ASSUMED_ROLE_PROFILE> \
  --region <REGION> --target <INSTANCE_ID>
```

You can inspect two kinds of records in your AWS account:

| Record | Where to configure and view it | What it shows |
| --- | --- | --- |
| API calls | In **CloudTrail > Event history**, search the target Region for `StartSession` and `TerminateSession`. Configure a CloudTrail trail for longer retention. | The assumed session identity, target, time, and other API details. It **does not include commands executed inside the shell**. [AWS: CloudTrail records](https://docs.aws.amazon.com/systems-manager/latest/userguide/monitoring-cloudtrail-logs.html) |
| Native shell content | Before access begins, enable delivery to customer-controlled CloudWatch Logs or S3 in **Systems Manager > Session Manager > Preferences**, and set retention and access permissions. Then inspect the log group or bucket. | Native shell session content captured after logging is enabled. Session Manager cannot log the contents of SSH over SSM or port forwarding tunnels. [AWS: session logging](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html) |

You can also look up `StartSession` events with the AWS CLI:

```bash
aws cloudtrail lookup-events --region <REGION> \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession
```

To validate the setup, use instances approved by the customer: confirm that each target host is `Online`, the AutoMQ operations role can access a tagged instance, an instance missing the required tag returns `AccessDenied`, and the new session appears in CloudTrail and the configured session log destination.
