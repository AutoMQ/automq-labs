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
standard Amazon Linux 2023 AMI through the public SSM parameter. Verify the
SSM Agent on the actual instance rather than assuming every AMI variant has
it installed. The agent uses the instance role to register with Systems
Manager and establish its message channels.
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

If the host is not `Online`, check the instance profile, Agent service and
logs, Region, DNS, and outbound 443 before granting operator access. On the
host, check `systemctl status amazon-ssm-agent` and
`/var/log/amazon/ssm/amazon-ssm-agent.log`.

## 2. Create a customer-owned operator role

Ask AutoMQ for the **specific AWS Principal ARN** that its operators use and
a customer-specific External ID. In your AWS account, create a dedicated IAM
role that trusts only that Principal. Replace both placeholders in this trust
policy; verify that `AssumeRole` fails when the External ID is absent or
incorrect. AutoMQ must separately allow its Principal to call
`sts:AssumeRole` on your role.
[AWS describes cross-account third-party access](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_common-scenarios_third-party.html).

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "<AUTOMQ_OPERATOR_PRINCIPAL_ARN>" },
    "Action": "sts:AssumeRole",
    "Condition": {
      "StringEquals": { "sts:ExternalId": "<CUSTOMER_EXTERNAL_ID>" }
    }
  }]
}
```

Attach the following permissions policy to that customer-owned role. Replace
the Region, account ID, and Console instance ID. The example uses both the
exact instance ARN and the case-sensitive EC2 instance tag
`automqVendor=automq`; the tag belongs on the **EC2 instance**, not only on
its IAM role or subnet. This Terraform example sets the tag on the Console
instance. If the instance is replaced, update the ARN in this policy.
[AWS shows how to restrict Session Manager by resource tag](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StartSessionOnConsole",
      "Effect": "Allow",
      "Action": "ssm:StartSession",
      "Resource": "arn:aws:ec2:<REGION>:<CUSTOMER_ACCOUNT_ID>:instance/<CONSOLE_INSTANCE_ID>",
      "Condition": {
        "StringEquals": { "ssm:resourceTag/automqVendor": "automq" }
      }
    },
    {
      "Sid": "UseShellDocument",
      "Effect": "Allow",
      "Action": "ssm:StartSession",
      "Resource": "arn:aws:ssm:<REGION>:<CUSTOMER_ACCOUNT_ID>:document/SSM-SessionManagerRunShell"
    },
    {
      "Sid": "ManageOwnSessions",
      "Effect": "Allow",
      "Action": [
        "ssm:ResumeSession",
        "ssm:TerminateSession",
        "ssmmessages:OpenDataChannel"
      ],
      "Resource": "arn:aws:ssm:<REGION>:<CUSTOMER_ACCOUNT_ID>:session/${aws:userid}-*"
    },
    {
      "Sid": "ProtectAccessTag",
      "Effect": "Deny",
      "Action": ["ec2:CreateTags", "ec2:DeleteTags"],
      "Resource": "arn:aws:ec2:<REGION>:<CUSTOMER_ACCOUNT_ID>:instance/*",
      "Condition": {
        "ForAnyValue:StringEquals": { "aws:TagKeys": ["automqVendor"] }
      }
    }
  ]
}
```

Check the actual owner of `SSM-SessionManagerRunShell` in your account and
adjust its document ARN if necessary. Keep control of who can set
`automqVendor` or change this operator role's policies; denying the two tag
APIs above does not constrain other identities or every resource-creation
path. This policy grants an interactive shell only. Add instance discovery
permissions if operators need them; grant `ssm:SendCommand` separately only
if remote command execution is required.

Give AutoMQ the operator role ARN, AWS account ID, Region, and Console
instance ID. AutoMQ operators assume the role using short-lived credentials
and the agreed External ID. They can then start a shell using AWS CLI and the
[Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html):

```bash
aws ssm start-session --profile <ASSUMED_OPERATOR_PROFILE> \
  --region <REGION> --target <CONSOLE_INSTANCE_ID>
```

Confirm the session opens on the expected host. The default Linux session
user, `ssm-user`, normally has sudo privileges; treat this as privileged host
access. Also test that this role cannot start a session on an instance outside
the policy's scope.

The data-plane nodes use the separate `cluster_instance_profile_arn` output.
This example does **not** attach `AmazonSSMManagedInstanceCore` to that role.
If you also need SSM host access to broker EC2 instances, add the required
SSM Agent permissions to their instance role, verify the tag on each target
EC2 instance, and extend the operator policy only to those approved instance
ARNs. Console instance permissions do not carry over to brokers.

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

