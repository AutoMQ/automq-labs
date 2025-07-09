# AutoMQ Open Source Deployment

This section provides various methods for deploying the open-source version of AutoMQ. Choose the one that best fits your environment and needs.

## Deployment Methods

### 1. [Docker Compose](./docker-compose/)

*   **Status**: ✅ Ready
*   **Use Case**: The quickest way to get a single-node or three-node AutoMQ cluster running on your local machine for development and testing. This setup uses MinIO as a local S3-compatible backend.

### 2. [Kubernetes (with Helm)](./kubernetes/)

*   **Status**: ✅ Ready
*   **Use Case**: A comprehensive guide for deploying AutoMQ on a Kubernetes cluster using the Bitnami Helm chart for Kafka. This is suitable for users who want to run AutoMQ in a cloud-native environment. It includes instructions for standard, multi-AZ, and mTLS-secured deployments.

### 3. [Ansible](./ansible/)

*   **Status**: 🚧 Planned
*   **Use Case**: This method will provide Ansible playbooks for automating the deployment of AutoMQ on a set of virtual machines. It is intended for users who prefer an Ansible-based workflow for infrastructure management.