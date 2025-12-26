# VPC 和 NAT Gateway 配置总结

## 功能概述

现在 Terraform 配置支持三种部署模式：

### 1. 创建新 VPC（默认模式）
- ✅ 自动创建新的 VPC
- ✅ 自动创建公有和私有子网
- ✅ 自动创建 NAT Gateway
- ✅ 自动创建 VPC Endpoints

**配置示例**：
```hcl
# 使用默认配置即可，无需额外设置
```

---

### 2. 使用现有 VPC（已有 NAT Gateway）
- ✅ 使用您指定的现有 VPC
- ✅ 使用现有的子网
- ❌ 不创建 NAT Gateway（假设您的 VPC 已配置）
- ✅ 创建 VPC Endpoints

**配置示例**：
```hcl
use_existing_vpc = true
existing_vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
existing_public_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
```

---

### 3. 使用现有 VPC + 创建 NAT Gateway（新功能）
- ✅ 使用您指定的现有 VPC
- ✅ 使用现有的子网
- ✅ **自动创建 NAT Gateway**
- ✅ 自动配置私有子网路由到 NAT Gateway
- ✅ 创建 VPC Endpoints

**配置示例**：
```hcl
use_existing_vpc = true
create_nat_gateway = true  # 新增：创建 NAT Gateway
existing_vpc_id = "vpc-xxxxxxxxxxxxxxxxx"
existing_private_subnet_ids = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]
existing_public_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]  # 必需！
```

**重要**：当 `create_nat_gateway = true` 时，**必须**提供 `existing_public_subnet_ids`

---

## 创建的资源

### 模式 3（使用现有 VPC + 创建 NAT Gateway）会创建：

1. **Elastic IP**：用于 NAT Gateway
2. **NAT Gateway**：部署在第一个公有子网
3. **路由规则**：为每个私有子网添加 0.0.0.0/0 -> NAT Gateway 的路由
4. **VPC Endpoints**：S3 和 EC2 endpoints

---

## 变量说明

| 变量名 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `use_existing_vpc` | bool | false | 是否使用现有 VPC |
| `create_nat_gateway` | bool | false | 是否在现有 VPC 中创建 NAT Gateway |
| `existing_vpc_id` | string | "" | 现有 VPC ID（use_existing_vpc=true 时必需） |
| `existing_private_subnet_ids` | list(string) | [] | 现有私有子网 IDs（use_existing_vpc=true 时必需） |
| `existing_public_subnet_ids` | list(string) | [] | 现有公有子网 IDs（create_nat_gateway=true 时必需） |

---

## 验证逻辑

配置包含以下验证：

1. ✅ 如果 `use_existing_vpc = true`，必须提供 `existing_vpc_id` 和 `existing_private_subnet_ids`
2. ✅ 如果 `create_nat_gateway = true`，必须提供 `existing_public_subnet_ids`

违反这些规则会在 `terraform plan` 时报错。

---

## 使用建议

### 何时使用模式 1（创建新 VPC）：
- 您想要一个全新的、隔离的网络环境
- 您没有现有的 VPC 约束
- 您希望 Terraform 管理所有网络资源

### 何时使用模式 2（现有 VPC，不创建 NAT）：
- 您的 VPC 已经有 NAT Gateway 配置
- 您想要最小化对现有基础设施的更改
- 您使用其他方式提供出站互联网访问（如 VPN、Direct Connect）

### 何时使用模式 3（现有 VPC + 创建 NAT）：
- ✨ 您有现有的 VPC 但没有 NAT Gateway
- ✨ 您想要 Terraform 管理 NAT Gateway
- ✨ 您的私有子网需要访问互联网

---

## 成本考虑

创建 NAT Gateway 会产生以下费用：
- NAT Gateway 小时费用：约 $0.045/小时
- 数据处理费用：约 $0.045/GB
- Elastic IP 费用（如果不使用）

**预估月成本**：约 $32-50/月（取决于数据传输量）

---

## 故障排查

### 错误：缺少公有子网
```
Error: When use_existing_vpc is true and create_nat_gateway is true, 
existing_public_subnet_ids must be provided
```
**解决**：在配置文件中添加 `existing_public_subnet_ids`

### 错误：路由表已存在默认路由
```
Error: A route with destination CIDR 0.0.0.0/0 already exists
```
**解决**：您的私有子网路由表已有默认路由，设置 `create_nat_gateway = false`

---

## 快速开始

1. 复制示例配置：
```bash
cp terraform.tfvars.example terraform.tfvars
```

2. 编辑 `terraform.tfvars`，选择合适的模式

3. 部署：
```bash
terraform init
terraform plan
terraform apply
```

更多详细信息，请参考：
- `README.md` - 完整使用说明
- `EXISTING_VPC_GUIDE.md` - 现有 VPC 使用指南
- `get-vpc-info.sh` - VPC 信息获取脚本
