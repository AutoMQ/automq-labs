# Deploy AutoMQ Enterprise on Kubernetes with Helm

This guide provides instructions for deploying the enterprise version of [AutoMQ](https://www.automq.com/) on a Kubernetes cluster using the managed Helm chart for Kafka.

AutoMQ is a cloud-native streaming platform that is fully compatible with the Kafka protocol. By leveraging Bitnami's widely-used Helm chart, you can easily deploy and manage AutoMQ in your Kubernetes environment.

## Prerequisites

Before you begin, ensure you have the following:

1.  **A Kubernetes Cluster**: If you don't have one, you can quickly provision a cluster on AWS EKS by following our [Terraform guide for AWS EKS](../../../byoc-examples/setup/kubernetes/aws/terraform/README.md).
2.  **Helm (v3.6.0+)**: The package manager for Kubernetes. You can verify your installation by running:
    ```shell
    helm version
    ```
    If you need to install it, follow the official [Helm installation guide](https://helm.sh/docs/intro/install/).

## Installation Steps

### 1. Configure `demo-values.yaml`

The key to deploying AutoMQ is to provide a custom `values.yaml` file that configures the AutoMQ Enterprise Kafka chart to use AutoMQ's container image and settings.

We provide some `demo-values.yaml` in this directory that is pre-configured for deploying AutoMQ on AWS using `r6in.large` instances and different credential type.
- AccessKey Credentials: [demo-static-values.yaml](static/demo-static-values.yaml)
- Instance profile Role Credentials: [demo-role-values.yaml](role/demo-role-values.yaml)

**Action:**

Edit the `demo-static-values.yaml` or `demo-role-values.yaml` file and customize it for your environment. You will need to replace the placeholder values (marked with `${...}`), such as the S3 bucket names (`ops-bucket`, `data-bucket`), AWS region, endpoint, AK/SK or instance profile role.

- For more details on available parameters, refer to the [AutoMQ Enterprise Kafka chart values](https://www.automq.com/docs/automq-cloud/appendix/helm-chart-values-readme).

- For more details on install AutoMQ Enterprise, refer to the [AutoMQ Enterprise Install](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart#install-automq).

- For more details on other advanced configurations, refer to the [AutoMQ Enterprise Other Advanced Configurations](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart#other-advanced-configurations).

- For more details on performance tuning, refer to the [AutoMQ Performance Tuning Guide](https://www.automq.com/docs/automq/deployment/performance-tuning-for-broker).

### 2. Install the Helm Chart

Once your `demo-values.yaml` file is ready, use the `helm install` command to deploy AutoMQ. We recommend using a version from the `31.x` series of the Bitnami Kafka chart for best compatibility.

**Action:**

Run the following command to install AutoMQ in a dedicated namespace:

```shell
helm install automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f static/demo-static-values.yaml \
  --version 5.3.2 \
  --namespace automq \
  --create-namespace
```

This command will create a new release named `automq-release` in the `automq` namespace.

## Managing the Deployment

### Upgrading the Deployment

To apply changes to your deployment after updating `demo-values.yaml`, use the `helm upgrade` command:

```shell
helm upgrade automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f demo-values.yaml \
  --version 5.3.2 \
  --namespace automq
```

### Uninstalling the Deployment

To completely remove the AutoMQ deployment from your cluster, use `helm uninstall`:

```shell
helm uninstall automq-release --namespace automq
kubectl delete pvc --all --namespace automq
```
This will delete all Kubernetes resources associated with the Helm release.

## Connect and Test the Cluster
### Headless service
1.  **Find the Headless Service**:
    Run the following command to find the AutoMQ Headless Service:
    ```shell
    kubectl get svc --namespace automq -l "app.kubernetes.io/component=controller" -w
    ```
2.  **Test with a Kafka Client**:
    Use headless service as the `--bootstrap-server` for your Kafka clients. using the command below:
    ```shell
    ./kafka-console-producer.sh \
      --bootstrap-server automq-release-automq-enterprise-controller-0.automq-release-automq-enterprise-controller-headless.automq.svc.cluster.local:9092 \
      --topic test-topic
    ```

### LoadBalancer
1.  **Find the External Address**:
    Run the following command and wait for the `EXTERNAL-IP` to be assigned. You can get and choose the LoadBalancer external IP using the command below:
    ```shell
    kubectl get svc --namespace automq -l "app.kubernetes.io/component=controller" -w
    ```
2.  **Test with a Kafka Client**:
    Port `9092` is used for client access.
    ```shell
    # Replace <EXTERNAL-IP> with the address from the previous step
    ./kafka-console-producer.sh \
      --bootstrap-server <EXTERNAL-IP>:9092 \
      --topic test-topic
    ```