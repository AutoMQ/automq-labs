# Deploy AutoMQ OSS on Kubernetes with Strimzi

This guide provides step-by-step instructions for deploying the open-source version of [AutoMQ](https://www.automq.com/) on a Kubernetes cluster using the Strimzi Helm chart for Kafka.

AutoMQ is a cloud-native streaming platform that is fully compatible with the Kafka protocol. By leveraging Strimzi's widely-adopted Helm chart, you can easily deploy and manage AutoMQ in your Kubernetes environment.

## Prerequisites

Before you begin, ensure you have the following:

1. **A Kubernetes Cluster**: If you don't have one, you can quickly provision a cluster on AWS EKS by following our [Terraform guide for AWS EKS](../../../../byoc-examples/setup/kubernetes/aws/terraform/README.md).
2. **Helm (v3.8.0+)**: The package manager for Kubernetes. You can verify your installation by running:
   ```shell
   helm version
   ```
   If you need to install it, follow the official [Helm installation guide](https://helm.sh/docs/intro/install/).

>Strimzi provides several types of operators. Unless otherwise specified, the following content refers to the Cluster Operator.

## Installation Steps

### Deploy Strimzi Operator

#### 1. Configure `strimzi-values.yaml`

The key to deploying Strimzi Operator is to provide a custom `values.yaml` file that configures the Strimzi Operator chart to use the appropriate container images and settings.

A pre-configured `strimzi-values.yaml` file is provided in this directory as your starting point. We recommend using the fixed version `0.47` of Strimzi to avoid compatibility issues.

The `strimzi-values.yaml` maps Kafka versions to AutoMQ container images via the `STRIMZI_KAFKA_IMAGES` environment variable. The current default configuration uses AutoMQ `1.6.5` (based on Kafka `3.9.1`).

**Action:**

Customize the `strimzi-values.yaml` file based on your requirements, or use the provided configuration as-is.

#### 2. Install the Helm Chart

Once your `strimzi-values.yaml` file is ready, use the `helm install` command to deploy the Strimzi Operator.

**Action:**

Run the following command to install the Strimzi Operator in a dedicated namespace:

```shell
helm install automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --version 0.47.0 \
  --namespace automq \
  --create-namespace \
  --values strimzi-values.yaml
```

This command will create a new release named `automq-strimzi-operator` in the `automq` namespace.

### Deploy AutoMQ Cluster

#### 1. Configure `automq-demo.yaml`

First, you'll need to prepare an `automq-demo.yaml` file. You can add additional parameters to meet your requirements - for more details, refer to the [Broker and Controller Configuration](https://www.automq.com/docs/automq/configuration/broker-and-controller-configuration).

We provide a pre-configured `automq-demo.yaml` file in this directory that is set up for deploying AutoMQ on AWS using `r6in.large` instances.

**Action:**

Edit the `automq-demo.yaml` file and customize it for your environment. You'll need to replace the placeholder values (marked with `${...}`), such as the S3 bucket names (`ops-bucket`, `data-bucket`), AWS region, and endpoint.

For more details on performance tuning and available parameters, refer to the [AutoMQ Performance Tuning Guide](https://www.automq.com/docs/automq/deployment/performance-tuning-for-broker) and the official [Kafka broker configuration tuning](https://strimzi.io/docs/operators/in-development/deploying#con-broker-config-properties-str).

If you want to run controllers and brokers in separate Strimzi node pools, use `automq-demo-split-roles.yaml` as the starting point. In that example, the `controller` pool uses only the `controller` role, while the `broker` pool uses only the `broker` role.

If you also want Kubernetes to place controllers and brokers on different node groups, use `automq-demo-split-roles-nodegroups.yaml` as the starting point. This example keeps the same Kafka role split and adds node affinity plus tolerations for separate EKS node groups. Replace `${controller-nodegroup}` and `${broker-nodegroup}` with your node group names, and update the custom label or taint values if your cluster uses different scheduling keys.

#### 2. Deploy the Cluster

Once your `automq-demo.yaml` file is ready, use the `kubectl apply` command to deploy AutoMQ.

**Action:**

Run the following command to install AutoMQ in the dedicated namespace:

```shell
kubectl apply -f automq-demo.yaml -n automq
```

This command will create a new AutoMQ cluster managed by the Strimzi Operator in the `automq` namespace.

For the split-role example, apply the alternate manifest instead:

```shell
kubectl apply -f automq-demo-split-roles.yaml -n automq
```

For the split-role example with separate EKS node groups, apply:

```shell
kubectl apply -f automq-demo-split-roles-nodegroups.yaml -n automq
```

### Controller and Broker Node Groups

The controller/broker split has two independent parts:

1. Kafka process roles are controlled by `KafkaNodePool.spec.roles`. Use `roles: [controller]` for controller-only nodes and `roles: [broker]` for broker-only nodes.
2. Kubernetes scheduling is controlled by `template.pod.affinity` and `template.pod.tolerations`. Use these fields when the controller and broker pods must run on different node groups.

On EKS, managed node groups are labeled with `eks.amazonaws.com/nodegroup`. You can combine that label with your own labels and taints to make the placement explicit. For example, the controller pool in `automq-demo-split-roles-nodegroups.yaml` matches the controller node group:

```yaml
roles:
  - controller
template:
  pod:
    tolerations:
      - key: "node-role.automq.io/strimzi-role"
        operator: "Equal"
        value: "controller"
        effect: "NoSchedule"
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: eks.amazonaws.com/nodegroup
                  operator: In
                  values:
                    - "${controller-nodegroup}"
                - key: node-role.automq.io/strimzi-role
                  operator: In
                  values:
                    - controller
```

The broker pool uses the same pattern with `roles: [broker]`, `${broker-nodegroup}`, and `value: broker`.

This node group separation is optional for AutoBalancer. AutoBalancer works with controller-only and broker-only Strimzi node pools as long as the broker pool exists and the AutoMQ storage, listener, and rack settings are configured correctly.

## Managing the Deployment

### Upgrading AutoMQ Version

To upgrade AutoMQ to a new version (e.g., from `1.6.0` to `1.6.5`), follow these steps in order:

#### Step 1: Update the image mapping

Edit `strimzi-values.yaml` to point the target Kafka version to the new AutoMQ image. For example, to upgrade to AutoMQ `1.6.5` (based on Kafka `3.9.1`):

```yaml
extraEnvs:
  - name: STRIMZI_KAFKA_IMAGES
    value: |
      3.9.0=automqinc/automq:1.6.0-strimzi
      3.9.1=automqinc/automq:1.6.5-strimzi
      4.0.0=quay.io/strimzi/kafka:0.47.0-kafka-4.0.0
```

Then apply the change to the Strimzi Operator:

```shell
helm upgrade automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --version 0.47.0 \
  --namespace automq \
  --values strimzi-values.yaml
```

#### Step 2: Update the Kafka version in the cluster spec

If the new AutoMQ version is based on a different Kafka version (e.g., upgrading from `3.9.0` to `3.9.1`), update `spec.kafka.version` in `automq-demo.yaml`:

```yaml
spec:
  kafka:
    version: 3.9.1
```

Then apply the change to trigger a rolling upgrade:

```shell
kubectl apply -f automq-demo.yaml -n automq
```

> **Important:** Always run `helm upgrade` first (Step 1), then `kubectl apply` (Step 2). The Operator must know the new image mapping before the cluster version change is applied.

### Upgrading Operator Configuration

To apply other changes to your Strimzi Operator deployment after updating `strimzi-values.yaml`, use the `helm upgrade` command:

```shell
helm upgrade automq-strimzi-operator oci://quay.io/strimzi-helm/strimzi-kafka-operator \
  --version 0.47.0 \
  --namespace automq \
  --values strimzi-values.yaml
```

To apply changes to your AutoMQ cluster after updating `automq-demo.yaml`, use the `kubectl apply` command:

```shell
kubectl apply -f automq-demo.yaml -n automq
```

### Uninstalling the Deployment

**Important:** When uninstalling, remove the AutoMQ cluster first, then the Strimzi Operator, to ensure proper cleanup.

#### 1. **Remove the AutoMQ Cluster**

```shell
kubectl delete -f automq-demo.yaml -n automq
```

Wait for the cluster resources to be fully deleted before proceeding to the next step.

#### 2. **Remove the Strimzi Operator**

```shell
helm uninstall automq-strimzi-operator --namespace automq
```

#### 3. **Remove the Namespace** (Recommended)

Since we created a dedicated namespace when deploying AutoMQ, it is recommended to remove it completely to ensure thorough cleanup.

```shell
kubectl delete namespace automq
```

This will delete all Kubernetes resources associated with the AutoMQ cluster and Strimzi Operator.
