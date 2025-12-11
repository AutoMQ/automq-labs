# Deploy AutoMQ Enterprise on Azure OpenShift

## Overview

This issue requests documentation and example configurations for deploying AutoMQ Enterprise Edition on Azure OpenShift (Azure Red Hat OpenShift or ARO).

## Requirements

### 1. Platform
- **Target Platform**: Azure OpenShift (Azure Red Hat OpenShift / ARO)
- **Deployment Method**: Helm chart deployment using AutoMQ Enterprise Helm chart

### 2. Storage Configuration
- **S3 WAL**: Use Azure Blob Storage for S3 WAL (Write-Ahead Log)
- **Storage Backend**: Azure Blob Storage containers for both data and operations buckets
- **Endpoint Configuration**: Configure Azure Blob Storage endpoint in the Helm values

### 3. Authentication & Authorization
- **Credentials Type**: Use Azure Service Principal credentials for authentication
- **Credential Format**: Service Principal with client ID, client secret, and tenant ID
- **Kafka ACL**: Support Plaintext authentication for Kafka ACL (no SASL/SSL required for ACL)

### 4. Network Exposure
- **Controller Service**: Expose Controller pods via Kubernetes Service (ClusterIP or NodePort)
- **Broker Service**: Expose Broker pods via Pod IP addresses (direct Pod IP access)
- **No LoadBalancer**: Do not use LoadBalancer service type (use Service or Pod IP instead)

## Expected Deliverables

1. **Helm Values File**: A complete `values.yaml` example file configured for Azure OpenShift deployment with:
   - Azure Blob Storage endpoint configuration
   - Service Principal credential configuration
   - Controller Service exposure settings
   - Broker Pod IP exposure configuration
   - Plaintext ACL settings

2. **Documentation**: A README.md file in `software-examples/kubernetes/azure/openshift/` directory that includes:
   - Prerequisites (Azure OpenShift cluster, Service Principal setup, Blob Storage containers)
   - Step-by-step deployment instructions
   - Configuration details for Azure Blob Storage
   - Service Principal setup guide
   - Network access patterns (Service vs Pod IP)
   - Testing and validation steps

## Infrastructure Prerequisites

Before deploying AutoMQ Enterprise on OpenShift, you need to prepare the Azure infrastructure:

1. **Use the shared infrastructure setup**: See [`infra-setup/azure/openshift/`](../../../../infra-setup/azure/openshift/) for Terraform configuration to create:
   - Azure Blob Storage account and containers
   - Managed Identity for Service Principal authentication

2. **Create the OpenShift cluster**: Create the Azure Red Hat OpenShift cluster through Azure Portal or CLI.

3. **Example Configuration**: Reference implementation showing:
   - How to configure Azure Blob Storage as S3-compatible storage
   - Service Principal credential injection (via environment variables or secrets)
   - Service and Pod IP exposure patterns
   - Plaintext ACL configuration

## Technical Details

### Azure Blob Storage Configuration
- Endpoint format: `https://<storage-account-name>.blob.core.windows.net`
- Path-style access configuration
- Container names for ops and data buckets

### Service Principal Credentials
- Client ID
- Client Secret
- Tenant ID
- Storage account access permissions (Blob Data Contributor role)

### Network Configuration
- Controller: Kubernetes Service (ClusterIP recommended for internal access)
- Broker: Direct Pod IP access (no Service abstraction)
- Port configuration: Standard Kafka port 9092

### Security
- Plaintext protocol for Kafka ACL (no encryption required)
- Service Principal for Azure Blob Storage access
- Network policies as per OpenShift requirements

## Related Documentation

- Existing AWS EKS deployment examples: `software-examples/kubernetes/aws/`
- Azure ARM templates: `byoc-examples/setup/azure/`
- Kubernetes deployment guides: `software-examples/kubernetes/`

## Priority

Medium - This would enable AutoMQ Enterprise deployment on Azure OpenShift, expanding platform support.


