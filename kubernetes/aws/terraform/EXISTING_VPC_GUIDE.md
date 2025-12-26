# 如何使用现有 VPC

本文档演示如何配置 Terraform 使用现有的 VPC 而非创建新的 VPC。

## 场景 1: 创建新 VPC（默认模式）

这是默认行为，无需额外配置。

```bash
terraform init
terraform plan
terraform apply
```

## 场景 2: 使用现有 VPC

### 步骤 1: 获取 VPC 和子网信息

首先，您需要获取现有 VPC 和子网的 ID。可以使用 AWS CLI：

```bash
# 列出 VPC
aws ec2 describe-vpcs --region ap-northeast-1

# 列出特定 VPC 的子网
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxxxx" --region ap-northeast-1
```

### 步骤 2: 创建配置文件

创建 `terraform.tfvars` 文件：

```hcl
# 基本配置
region = "ap-northeast-1"
resource_suffix = "automqlab"

# EKS 节点组配置
node_group = {
  name          = "automq-node-group"
  desired_size  = 4
  max_size      = 10
  min_size      = 3
  instance_type = "c6g.2xlarge"
  ami_type      = "AL2_ARM_64"
}

# 使用现有 VPC
use_existing_vpc = true
existing_vpc_id  = "vpc-0123456789abcdef0"

# 私有子网（必需）
existing_private_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
  "subnet-0123456789abcdef2"
]

# 公有子网（可选）
existing_public_subnet_ids = [
  "subnet-0123456789abcdef3",
  "subnet-0123456789abcdef4",
  "subnet-0123456789abcdef5"
]
```

### 步骤 3: 验证配置

```bash
# 初始化 Terraform
terraform init

# 查看执行计划
terraform plan

# 验证以下内容：
# ✓ 没有创建新的 VPC（module.network.module.vpc 显示 "0 to add"）
# ✓ VPC endpoints 引用现有 VPC
# ✓ EKS 资源使用现有子网
```

### 步骤 4: 应用配置

```bash
terraform apply
```

## 现有 VPC 的要求

使用现有 VPC 时，请确保满足以下要求：

1. **DNS 支持**: VPC 必须启用 DNS 主机名和 DNS 支持
   ```bash
   aws ec2 modify-vpc-attribute --vpc-id vpc-xxxxx --enable-dns-hostnames
   aws ec2 modify-vpc-attribute --vpc-id vpc-xxxxx --enable-dns-support
   ```

2. **私有子网**: 至少需要一个私有子网用于 EKS 节点组
   - 私有子网必须能够访问互联网（通过 NAT Gateway 或类似方式）

3. **多可用区**: 建议子网分布在不同的可用区以实现高可用性

4. **子网标签**: 对于 EKS，建议为子网添加适当的标签：
   ```bash
   # 私有子网
   aws ec2 create-tags --resources subnet-xxxxx \
     --tags Key=kubernetes.io/role/internal-elb,Value=1

   # 公有子网
   aws ec2 create-tags --resources subnet-xxxxx \
     --tags Key=kubernetes.io/role/elb,Value=1
   ```

## 验证部署

部署完成后，检查创建的资源：

```bash
# 查看 EKS 集群
aws eks describe-cluster --name <cluster-name> --region ap-northeast-1

# 查看节点组
aws eks describe-nodegroup --cluster-name <cluster-name> \
  --nodegroup-name automq-node-group --region ap-northeast-1

# 查看 VPC endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --region ap-northeast-1
```

## 故障排查

### 错误: 缺少必需变量

```
Error: When use_existing_vpc is true, existing_vpc_id and existing_private_subnet_ids must be provided
```

**解决方案**: 确保在 `terraform.tfvars` 中设置了 `existing_vpc_id` 和 `existing_private_subnet_ids`。

### 错误: 子网不属于指定 VPC

```
Error: Subnet subnet-xxxxx does not belong to VPC vpc-yyyyy
```

**解决方案**: 验证所有子网 ID 是否都属于指定的 VPC。

### 错误: 无法访问 AWS API

```
Error: No valid credential sources found
```

**解决方案**: 配置 AWS 凭证：
```bash
aws configure
# 或者
aws sso login --profile your-profile
```

## 清理资源

删除创建的资源（不会删除现有 VPC）：

```bash
terraform destroy
```

注意: 这只会删除 Terraform 创建的资源（EKS 集群、节点组、VPC endpoints 等），不会删除您指定的现有 VPC 和子网。
