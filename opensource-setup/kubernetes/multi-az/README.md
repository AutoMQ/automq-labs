# Deploy a Multi-AZ AutoMQ Cluster to Eliminate Cross-Zone Traffic Costs

This guide explains how to deploy AutoMQ across multiple Availability Zones (AZs) on Kubernetes. This setup is designed to eliminate inter-zone data transfer costs, which can be a significant expense in cloud environments like AWS and GCP.

## How It Works

AutoMQ's **Zone Router** feature intelligently routes traffic to ensure that clients communicate with brokers in the same AZ whenever possible. This is achieved through a combination of server-side configurations and a rack-aware client setup. When a client in `zone-a` needs to fetch data, the system ensures it connects to a broker replica also in `zone-a`, thus avoiding network charges.

For a detailed explanation of the mechanism, please refer to our official documentation:
*   [**Overview of Eliminating Inter-Zone Traffic**](https://www.automq.com/docs/automq/eliminate-inter-zone-traffics/overview)

## Prerequisites

Ensure you have met the prerequisites outlined in the main [Kubernetes deployment guide](../bitnami/README.md), including having a running Kubernetes cluster and Helm installed. Your Kubernetes cluster must span multiple availability zones.

## Configuration for Multi-AZ Deployment

The key to a multi-AZ deployment lies in the `demo-multi-az-values.yaml` file. It contains specific configurations to enable zone awareness and balanced pod distribution.

### Key Configuration Parameters

1.  **`topologySpreadConstraints`**:
    This standard Kubernetes feature ensures that broker and controller pods are distributed evenly across different availability zones. It prevents all pods from being scheduled into a single zone.
    ```yaml
    topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            app.kubernetes.io/component: broker
    ```

2.  **`brokerRackAssignment`**:
    This setting tells AutoMQ how to determine the "rack" (i.e., the Availability Zone) of a broker. For cloud environments, this can often be done automatically.
    ```yaml
    # aws-az and azure are supported here
    brokerRackAssignment: aws-az
    ```
    *   `aws-az`: (Recommended for AWS) AutoMQ automatically discovers the AZ from the node's metadata.
    *   `azure`: (Recommended for Azure) AutoMQ automatically discovers the AZ from the node's metadata.

3.  **`automq.zonerouter.channels`**:
    This is the core setting that activates the Zone Router feature. It requires the same S3 bucket information as your data buckets and enables the brokers to coordinate traffic routing within zones.
    ```yaml
    # Enable this configuration to allow the zone router to eliminate cross-zone traffic.
    # Apply it only for AWS and GCP, as other cloud vendors do not charge for cross-zone traffic.
    automq.zonerouter.channels=0@s3://${data-bucket}?region=${region}&endpoint=${endpoint}
    ```

## Deployment Steps

1.  **Edit `demo-multi-az-values.yaml`**:
    Open the `demo-multi-az-values.yaml` file and replace the placeholder values for your S3 buckets (`${ops-bucket}`, `${data-bucket}`), AWS region, and endpoint.

2.  **Install the Helm Chart**:
    Use the `helm install` command with the multi-az values file.
    ```shell
    helm install automq-multi-az oci://registry-1.docker.io/bitnamicharts/kafka \
      -f demo-multi-az-values.yaml \
      --version 31.5.0 \
      --namespace automq \
      --create-namespace
    ```

## Important: Configure Your Clients for Rack Awareness

Server-side configuration is only half the solution. To eliminate cross-AZ traffic, your Kafka clients **must** be configured to be rack-aware. This allows them to identify their own zone and connect to a broker in the same zone.

Please follow the detailed instructions in our documentation to configure your clients:
*   [**Client Configuration for Eliminating Inter-Zone Traffic**](https://www.automq.com/docs/automq/eliminate-inter-zone-traffics/client-configuration)

## Verifying the Setup

After deployment, you can confirm that cross-AZ traffic is eliminated by monitoring your cloud provider's network metrics. For AWS users, we provide a specific guide on how to do this using AWS Cost Explorer.

*   [**How to Monitor Inter-Zone Traffic on AWS**](https://www.automq.com/docs/automq/eliminate-inter-zone-traffics/monitor-inter-zone-traffic)
