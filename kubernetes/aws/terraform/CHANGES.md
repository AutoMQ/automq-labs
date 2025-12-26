# 变更总结 - 支持现有 VPC 和 NAT Gateway 创建

## 概述
为 `kubernetes/aws/terraform` 目录添加了对使用现有 VPC 的支持，并支持在现有 VPC 中创建 NAT Gateway。

## 主要变更

### 1. 新增变量（`variables.tf`）
- ✅ `use_existing_vpc` - 是否使用现有 VPC
- ✅ `existing_vpc_id` - 现有 VPC ID
- ✅ `existing_private_subnet_ids` - 现有私有子网 IDs
- ✅ `existing_public_subnet_ids` - 现有公有子网 IDs
- ✅ `create_nat_gateway` - **新增**：是否在现有 VPC 中创建 NAT Gateway

### 2. 修改文件

#### `main.tf`
- 添加变量验证逻辑
- 传递新变量到 network 模块

#### `network/main.tf`
- 使用 `count` 条件控制 VPC 模块创建
- 添加数据源获取现有 VPC 和子网信息
- **新增**：创建 NAT Gateway 资源（当 `create_nat_gateway = true`）
- **新增**：创建 Elastic IP 用于 NAT Gateway
- **新增**：自动配置私有子网路由表指向 NAT Gateway
- 修改 VPC Endpoints 支持现有 VPC

#### `network/outputs.tf`
- 修改输出以支持现有 VPC 和新建 VPC 两种模式

#### `network/variables.tf`
- 添加新变量定义

### 3. 新增文档

#### `terraform.tfvars.example`
- 提供三种部署模式的配置示例

#### `EXISTING_VPC_GUIDE.md`（中文）
- 详细说明如何使用现有 VPC
- 包含三种场景的配置步骤
- 提供验证和故障排查指南

#### `NAT_GATEWAY_GUIDE.md`（中文）
- NAT Gateway 功能总结
- 三种部署模式对比
- 成本考虑和使用建议

#### `TEST_PLAN.md`
- 详细的测试计划
- 验证检查清单

#### `get-vpc-info.sh`
- 帮助脚本，用于获取 VPC 和子网信息
- 自动生成 terraform.tfvars 配置
- 验证 VPC 要求（DNS 设置、多 AZ 等）

#### `README.md` 更新
- 添加三种配置选项说明
- 更新使用指南

## 功能特性

### 支持的三种部署模式：

#### 模式 1：创建新 VPC（默认）
```hcl
# 无需额外配置
```

#### 模式 2：使用现有 VPC
```hcl
use_existing_vpc = true
existing_vpc_id = "vpc-xxx"
existing_private_subnet_ids = ["subnet-xxx", ...]
```

#### 模式 3：使用现有 VPC + 创建 NAT Gateway ⭐新功能
```hcl
use_existing_vpc = true
create_nat_gateway = true
existing_vpc_id = "vpc-xxx"
existing_private_subnet_ids = ["subnet-xxx", ...]
existing_public_subnet_ids = ["subnet-yyy", ...]  # 必需
```

## 验证状态

✅ Terraform 语法验证通过
✅ 所有模块正确连接
✅ 变量验证逻辑正常
✅ 条件资源创建逻辑正确

## 需要的后续测试

建议在实际 AWS 环境中测试：

1. 创建新 VPC 模式（确保没有破坏原有功能）
2. 使用现有 VPC 模式（不创建 NAT Gateway）
3. 使用现有 VPC + 创建 NAT Gateway 模式（新功能）

## 使用示例

```bash
# 1. 复制示例配置
cp terraform.tfvars.example terraform.tfvars

# 2. 编辑配置（根据需要选择模式）
vim terraform.tfvars

# 3. 初始化和部署
terraform init
terraform plan
terraform apply
```

## 安全性和最佳实践

- ✅ 验证逻辑防止配置错误
- ✅ 使用条件表达式避免资源冲突
- ✅ 保持向后兼容（默认行为不变）
- ✅ 清晰的文档和示例
- ✅ 支持多 AZ 部署

## 成本影响

如果启用 `create_nat_gateway = true`：
- NAT Gateway: ~$32-50/月
- Elastic IP: 如果使用则免费，否则收费

## 回滚方案

如需回滚到之前版本：
```bash
git checkout <previous-commit>
terraform init -upgrade
```

原有配置完全兼容，无需修改现有 terraform.tfvars 文件。
