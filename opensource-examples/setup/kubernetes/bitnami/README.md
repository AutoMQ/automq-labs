# Deploy AutoMQ OSS on Kubernetes with Helm

This guide provides instructions for deploying the open-source version of [AutoMQ](https://www.automq.com/) on a Kubernetes cluster using the Bitnami Helm chart for Kafka.

AutoMQ is a cloud-native streaming platform that is fully compatible with the Kafka protocol. By leveraging Bitnami's widely-used Helm chart, you can easily deploy and manage AutoMQ in your Kubernetes environment.

## Prerequisites

Before you begin, ensure you have the following:

1.  **A Kubernetes Cluster**: If you don't have one, you can quickly provision a cluster on AWS EKS by following our [Terraform guide for AWS EKS](../../../../byoc-examples/setup/kubernetes/aws/terraform/README.md).
2.  **Helm (v3.8.0+)**: The package manager for Kubernetes. You can verify your installation by running:
    ```shell
    helm version
    ```
    If you need to install it, follow the official [Helm installation guide](https://helm.sh/docs/intro/install/).

## Installation Steps

### 1. Configure `demo-values.yaml`

The key to deploying AutoMQ is to provide a custom [values.yaml](demo-values.yaml) file that configures the Bitnami Kafka chart to use AutoMQ's container image and settings.

We provide a `demo-values.yaml` in this directory that is pre-configured for deploying AutoMQ on AWS using `m7g.xlarge` instances.

**Action:**

Edit the `demo-values.yaml` file and customize it for your environment. You will need to replace the placeholder values (marked with `${...}`), such as the S3 bucket names (`ops-bucket`, `data-bucket`), AWS region, and endpoint.

For more details on performance tuning and available parameters, refer to the [AutoMQ Performance Tuning Guide](https://www.automq.com/docs/automq/deployment/performance-tuning-for-broker) and the official [Bitnami Kafka chart values](https://github.com/bitnami/charts/blob/main/bitnami/kafka/values.yaml).

### 2. Install the Helm Chart

Once your `demo-values.yaml` file is ready, use the `helm install` command to deploy AutoMQ. We recommend using a version from the `31.x` series of the Bitnami Kafka chart for best compatibility.

**Action:**

Run the following command to install AutoMQ in a dedicated namespace:

```shell
helm install automq-release oci://registry-1.docker.io/bitnamicharts/kafka \
  -f demo-values.yaml \
  --version 31.5.0 \
  --namespace automq \
  --create-namespace
```

This command will create a new release named `automq-release` in the `automq` namespace.

## Managing the Deployment

### Upgrading the Deployment

To apply changes to your deployment after updating `demo-values.yaml`, use the `helm upgrade` command:

```shell
helm upgrade automq-release oci://registry-1.docker.io/bitnamicharts/kafka \
  -f demo-values.yaml \
  --version 31.5.0 \
  --namespace automq
```

### Uninstalling the Deployment

To completely remove the AutoMQ deployment from your cluster, use `helm uninstall`:

```shell
helm uninstall automq-release --namespace automq
```

This will delete all Kubernetes resources associated with the Helm release.