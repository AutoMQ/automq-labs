#!/bin/bash

# Script to help retrieve existing VPC and subnet information
# Usage: ./get-vpc-info.sh [region]

set -e

REGION=${1:-ap-northeast-1}

echo "========================================="
echo "Retrieving VPC and Subnet Information"
echo "Region: $REGION"
echo "========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# List all VPCs
echo "Available VPCs in $REGION:"
echo "-------------------------"
aws ec2 describe-vpcs \
    --region "$REGION" \
    --query 'Vpcs[].[VpcId, CidrBlock, Tags[?Key==`Name`].Value | [0], IsDefault]' \
    --output table

echo ""
echo "Enter VPC ID to get subnet details (or press Ctrl+C to exit):"
read -r VPC_ID

if [ -z "$VPC_ID" ]; then
    echo "No VPC ID provided. Exiting."
    exit 1
fi

echo ""
echo "VPC Details for $VPC_ID:"
echo "-------------------------"
aws ec2 describe-vpcs \
    --region "$REGION" \
    --vpc-ids "$VPC_ID" \
    --query 'Vpcs[0].[VpcId, CidrBlock, EnableDnsHostnames, EnableDnsSupport]' \
    --output table

echo ""
echo "Subnets in VPC $VPC_ID:"
echo "-------------------------"

# Get private subnets
echo ""
echo "Private Subnets:"
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?MapPublicIpOnLaunch==`false`].[SubnetId, CidrBlock, AvailabilityZone, Tags[?Key==`Name`].Value | [0]]' \
    --output table)

echo "$PRIVATE_SUBNETS"

PRIVATE_SUBNET_IDS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' \
    --output text | tr '\t' '\n')

# Get public subnets
echo ""
echo "Public Subnets:"
PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?MapPublicIpOnLaunch==`true`].[SubnetId, CidrBlock, AvailabilityZone, Tags[?Key==`Name`].Value | [0]]' \
    --output table)

echo "$PUBLIC_SUBNETS"

PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?MapPublicIpOnLaunch==`true`].SubnetId' \
    --output text | tr '\t' '\n')

# Generate terraform.tfvars content
echo ""
echo "========================================="
echo "Terraform Configuration"
echo "========================================="
echo ""
echo "Add the following to your terraform.tfvars file:"
echo ""
cat << EOF
# Use existing VPC configuration
region = "$REGION"
use_existing_vpc = true
existing_vpc_id = "$VPC_ID"

# Private subnets (required)
existing_private_subnet_ids = [
EOF

# Print private subnet IDs
echo "$PRIVATE_SUBNET_IDS" | while IFS= read -r subnet; do
    if [ -n "$subnet" ]; then
        echo "  \"$subnet\","
    fi
done

cat << 'EOF'
]

# Public subnets (optional)
existing_public_subnet_ids = [
EOF

# Print public subnet IDs
echo "$PUBLIC_SUBNET_IDS" | while IFS= read -r subnet; do
    if [ -n "$subnet" ]; then
        echo "  \"$subnet\","
    fi
done

echo "]"
echo ""

echo "========================================="
echo "VPC Requirements Check"
echo "========================================="
echo ""

# Check DNS settings
DNS_HOSTNAMES=$(aws ec2 describe-vpc-attribute \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --attribute enableDnsHostnames \
    --query 'EnableDnsHostnames.Value' \
    --output text)

DNS_SUPPORT=$(aws ec2 describe-vpc-attribute \
    --region "$REGION" \
    --vpc-id "$VPC_ID" \
    --attribute enableDnsSupport \
    --query 'EnableDnsSupport.Value' \
    --output text)

if [ "$DNS_HOSTNAMES" = "true" ]; then
    echo "✓ DNS hostnames: Enabled"
else
    echo "✗ DNS hostnames: Disabled (needs to be enabled)"
    echo "  Run: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames --region $REGION"
fi

if [ "$DNS_SUPPORT" = "true" ]; then
    echo "✓ DNS support: Enabled"
else
    echo "✗ DNS support: Disabled (needs to be enabled)"
    echo "  Run: aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support --region $REGION"
fi

# Count subnets in different AZs
PRIVATE_AZS=$(aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'Subnets[?MapPublicIpOnLaunch==`false`].AvailabilityZone' \
    --output text | tr '\t' '\n' | sort -u | wc -l)

echo ""
echo "Private subnets span $PRIVATE_AZS availability zone(s)"
if [ "$PRIVATE_AZS" -ge 2 ]; then
    echo "✓ Multi-AZ configuration: Good for high availability"
else
    echo "⚠ Single-AZ configuration: Consider adding subnets in other AZs for HA"
fi

echo ""
echo "Done!"
