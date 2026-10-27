# 在 AWS EC2 BYOC 环境中配置 SSM 运维通道

您可以通过 AWS Systems Manager（SSM）Session Manager，为 AutoMQ BYOC 环境建立受控的运维通道。发生需要主机排查的问题时，获您授权的 AutoMQ 运维人员可进入指定的控制台或数据面 EC2 主机。您在自己的 AWS 账号中管理授权范围、访问记录和撤销操作。

本文使用 **Session Manager 原生 Shell**：由 EC2 上的 SSM Agent 主动连接 AWS 服务，运维人员无需 SSH 私钥，也无需为主机开放入站 TCP 22。它与通过 SSM 隧道运行 SSH 不同；后者仍需要 `sshd` 和 SSH 凭据，且无法记录隧道内的命令内容。[AWS：Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) · [AWS：SSH over SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html)

## 了解访问流程

1. 您让目标 EC2 的 SSM Agent 注册到 AWS Systems Manager，并允许主机通过出站 HTTPS 443 连接本 Region 的 SSM 服务。
2. 您在客户账号中创建 **SSM 运维 Role**。该 Role 只信任 AutoMQ 提供的指定 IAM Role，并要求双方约定的客户专属 External ID。
3. AutoMQ 运维人员通过其受控身份获取临时凭据，调用 `sts:AssumeRole` 进入您创建的 Role，再对您授权的 EC2 发起 `ssm:StartSession`。
4. 您可随时修改目标实例范围或撤销 Role，并在客户账号中查看访问记录。

## 准备控制台和数据面 EC2

### 1. 检查并启动 SSM Agent

控制台和每台需要接受 SSM 连接的数据面 EC2 都必须运行 SSM Agent。此示例使用 Amazon Linux 2023 AMI。先在目标主机检查 Agent 是否已安装：

```bash
rpm -q amazon-ssm-agent
```

如果显示未安装，再执行安装。更换其他操作系统时，请按 [AWS 安装指南](https://docs.aws.amazon.com/systems-manager/latest/userguide/manually-install-ssm-agent-linux.html)选择对应方法；标准 AMI 是否预装 Agent 可查阅 [AWS 预装列表](https://docs.aws.amazon.com/systems-manager/latest/userguide/ami-preinstalled-agent.html)。

```bash
sudo dnf install -y amazon-ssm-agent
```

安装检查完成后，启动 Agent 并设置开机自启：

```bash
sudo systemctl enable --now amazon-ssm-agent
```

确认服务正在运行：

```bash
sudo systemctl status amazon-ssm-agent
```

### 2. 给目标主机的 instance profile 授权

SSM Agent 需要通过主机现有 instance profile 的 IAM Role 向 Systems Manager 注册并建立消息通道。请在该 Role 上附加 AWS 托管策略 `AmazonSSMManagedInstanceCore`；保留主机原有的应用权限。[AWS：实例侧权限](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html)

此示例的 [Console Terraform](../automq-console/iam.tf) **已经**把该策略附加到控制台 EC2 的 Role。数据面节点使用另一个 Role。若要让数据面主机也接受 SSM 连接，请在 `automq-console` 目录取得节点 Role 名称：

```bash
terraform output -raw cluster_role_name
```

然后在客户账号中附加策略：

```bash
aws iam attach-role-policy --role-name <CLUSTER_ROLE_NAME> \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

确认策略已附加：

```bash
aws iam list-attached-role-policies --role-name <CLUSTER_ROLE_NAME>
```

若您使用其他控制台部署模板，也可对其**现有** EC2 Role 执行同一命令；本示例的控制台 Role 无需重复操作。

### 3. 确认网络与注册状态

目标 EC2 需要通过出站 HTTPS 443 访问同一 Region 的 `ssm` 和 `ssmmessages` 服务。您可以使用现有互联网/NAT 路径，或配置 Interface VPC Endpoint；后者需要 Private DNS 和允许实例访问的 Endpoint 安全组规则。旧 Region 或旧版 Agent 可能还需 `ec2messages`。[AWS：Systems Manager VPC Endpoint](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)

在 **AWS Systems Manager > Fleet Manager > Managed nodes** 中确认每台目标主机为 `Online`。也可查询指定实例：

```bash
aws ssm describe-instance-information --region <REGION> \
  --filters Key=InstanceIds,Values=<INSTANCE_ID>
```

若主机未显示 `Online`，先检查 Agent 服务、instance profile、出站网络、DNS 与 `/var/log/amazon/ssm/amazon-ssm-agent.log`。[AWS：排查 SSM Agent](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-ssm-agent.html)

## 创建客户侧 SSM 运维 Role

本目录的 [Terraform 示例](ssm-operator.tf)仅创建客户侧运维 Role，并按目标 EC2 instance ID 与 Tag 限制会话访问。它不会读取或修改控制台、集群的 Terraform state。

部署控制台后，在 `automq-console` 目录获取以下输出：

```bash
terraform output -raw console_instance_id
```

在本目录创建本地 `terraform.tfvars`，将占位符替换为实际值。首次可只授权控制台；需要访问数据面时，再把经过确认的 Broker EC2 instance ID 加入 `instance_ids`。该文件及 Terraform state 包含 External ID，应存放在受控位置。

```hcl
region          = "<REGION>"
automq_role_arn = "arn:aws:iam::<AUTOMQ_ACCOUNT_ID>:role/<AUTOMQ_OPERATOR_ROLE>"
external_id     = "<CUSTOMER_SPECIFIC_EXTERNAL_ID>"
instance_ids    = ["<CONSOLE_INSTANCE_ID>"]
```

默认创建的 Role 名为 `automq-ssm-operator`；如果该账号需要多个运维 Role，可以另设 `role_name`。在客户账号中确认当前 AWS 身份，然后初始化、检查计划并部署：

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

部署后取得客户侧运维 Role ARN，提供给 AutoMQ：

```bash
terraform output -raw ssm_operator_role_arn
```

您也可以用 AWS CLI 查看该 Role 的信任策略和会话权限：

```bash
aws iam get-role --role-name <ROLE_NAME>
```

```bash
aws iam get-role-policy --role-name <ROLE_NAME> --policy-name ssm-operator
```

请同时告知 AutoMQ 您的 AWS 账号 ID、Region 和允许访问的实例 ID。AutoMQ 需要在其自身账号中允许指定 IAM Role 调用 `sts:AssumeRole`，并在请求中传入约定的 External ID。

## 确认权限边界与审计记录

本目录创建的 Role 只信任参数指定的 AutoMQ IAM Role，并要求正确的 `sts:ExternalId`。因此，只有获得该 AutoMQ Role 使用权限的人员或流程，才能尝试 AssumeRole；AutoMQ 负责管理其内部人员权限。客户侧策略进一步要求目标 **EC2 实例 ID 在 `instance_ids` 中**，且该实例具有大小写完全一致的 `automqVendor=automq` Tag。只有 Role 或 AutoMQ Instance 上存在该 Tag 不够。假设后的 Role 被显式禁止给 EC2 创建或删除这个访问边界 Tag；您还应限制其他身份修改该 Tag 或运维 Role。[AWS：按 Tag 限制 Session Manager 访问](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html)

用 AWS CLI 检查目标 EC2 上的 Tag：

```bash
aws ec2 describe-tags --region <REGION> \
  --filters Name=resource-id,Values=<INSTANCE_ID> Name=key,Values=automqVendor
```

本配置授予 Session Manager 原生 Shell 权限，不授予 `ssm:SendCommand` 或 SSH over SSM。运维人员使用短期凭据和 [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)进入获授权主机；Linux 默认会话用户 `ssm-user` 通常具有 sudo 权限，请将其视为高权限主机访问。

AutoMQ 运维人员先核对所使用的临时身份，再发起会话：

```bash
aws sts get-caller-identity --profile <AUTOMQ_ASSUMED_ROLE_PROFILE>
```

```bash
aws ssm start-session --profile <AUTOMQ_ASSUMED_ROLE_PROFILE> \
  --region <REGION> --target <INSTANCE_ID>
```

客户可在自己的 AWS 账号中分别查看两类记录：

| 记录 | 配置与查看位置 | 能看到什么 |
| --- | --- | --- |
| API 调用 | **CloudTrail > Event history**，在目标 Region 查询 `StartSession`、`TerminateSession`；需长期保留时配置 CloudTrail trail。 | AssumeRole 后的会话身份、目标及调用时间等 API 信息；**不包含 Shell 内执行的命令**。[AWS：CloudTrail 记录](https://docs.aws.amazon.com/systems-manager/latest/userguide/monitoring-cloudtrail-logs.html) |
| 原生 Shell 内容 | 在 **Systems Manager > Session Manager > Preferences** 中，提前启用发送至客户控制的 CloudWatch Logs 或 S3，并设置保留期和访问权限；随后到对应 Log Group 或 Bucket 查看。 | 启用日志后产生的原生 Shell 会话内容。SSH over SSM 和端口转发的隧道内容无法由 Session Manager 记录。[AWS：会话日志](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html) |

也可用 AWS CLI 查询 CloudTrail 中的 `StartSession` 事件：

```bash
aws cloudtrail lookup-events --region <REGION> \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession
```

配置完成后，用客户认可的实例验收：目标主机为 `Online`；AutoMQ 运维 Role 能进入已授权实例；实例不在清单中或缺少授权 Tag 时返回 `AccessDenied`；客户能在 CloudTrail 和所选会话日志目的地找到新会话的记录。
