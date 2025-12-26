# Test Plan for VPC Configuration

## Test Case 1: Create New VPC (Default Mode)

### Configuration
- Use default variables (use_existing_vpc = false)

### Expected Results
- New VPC should be created with CIDR 10.0.0.0/16
- 3 public subnets and 3 private subnets should be created
- NAT Gateway should be created
- VPC endpoints for S3 and EC2 should be created
- EKS cluster should use the newly created subnets

### Test Commands
```bash
cd /Users/keqing/automq-labs/automq-labs/kubernetes/aws/terraform
terraform init
terraform plan
# Review the plan to ensure new VPC resources are being created
```

---

## Test Case 2: Use Existing VPC

### Configuration
Create a `terraform.tfvars` file with:
```hcl
use_existing_vpc = true
existing_vpc_id = "vpc-xxxxx"  # Replace with actual VPC ID
existing_private_subnet_ids = [
  "subnet-xxxxx",
  "subnet-yyyyy",
  "subnet-zzzzz"
]
existing_public_subnet_ids = [
  "subnet-aaaaa",
  "subnet-bbbbb",
  "subnet-ccccc"
]
```

### Expected Results
- No new VPC should be created
- VPC endpoints should be created in the existing VPC
- Security groups should be created in the existing VPC
- EKS cluster should use the specified existing subnets

### Test Commands
```bash
cd /Users/keqing/automq-labs/automq-labs/kubernetes/aws/terraform
terraform init
terraform plan
# Review the plan to ensure:
# 1. No new VPC is being created (module.network.module.vpc will show "0 to add")
# 2. VPC endpoints reference the existing VPC
# 3. EKS resources reference the existing subnets
```

---

## Test Case 3: Validation - Missing Required Variables

### Configuration
```hcl
use_existing_vpc = true
# Missing: existing_vpc_id and existing_private_subnet_ids
```

### Expected Results
- Terraform should fail validation
- Error message should indicate missing required variables

### Test Commands
```bash
cd /Users/keqing/automq-labs/automq-labs/kubernetes/aws/terraform
terraform init
terraform plan
# Should fail with validation error
```

---

## Verification Checklist

After running `terraform plan`, verify:

### For New VPC Mode:
- [ ] VPC module shows resources being created
- [ ] 3 public subnets planned
- [ ] 3 private subnets planned
- [ ] 1 NAT Gateway planned
- [ ] 2 VPC endpoints planned (S3 and EC2)
- [ ] EKS cluster references new VPC ID
- [ ] Node group uses new private subnets

### For Existing VPC Mode:
- [ ] VPC module shows 0 resources being created
- [ ] Data sources fetch existing VPC info
- [ ] Data sources fetch existing subnet info
- [ ] 2 VPC endpoints planned (S3 and EC2)
- [ ] Security groups reference existing VPC ID
- [ ] EKS cluster references existing VPC ID
- [ ] Node group uses existing private subnets

### General:
- [ ] No syntax errors in Terraform code
- [ ] terraform validate succeeds
- [ ] terraform plan completes without errors
- [ ] All outputs are properly configured
