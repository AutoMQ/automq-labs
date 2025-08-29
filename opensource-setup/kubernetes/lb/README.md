# Deploy AutoMQ with External Access via LoadBalancer

This guide explains how to deploy an AutoMQ cluster on Kubernetes and expose it externally using a Service of type `LoadBalancer`. This setup is ideal for environments where you need to grant access to the cluster from outside the Kubernetes network, such as for clients running on-premises or in other VPCs.

## How It Works

This configuration uses the Bitnami Kafka Helm chart's built-in support for external access. When enabled, the chart provisions `LoadBalancer` services, which instruct the cloud provider (like AWS, GCP, or Azure) to create a network load balancer with a public IP address. This load balancer then routes external traffic to the AutoMQ brokers.

The `autoDiscovery` feature further simplifies connectivity by automatically detecting the load balancer's public address and configuring it as the advertised listener for the brokers.

## Prerequisites

Ensure you have met the prerequisites outlined in the main [Kubernetes deployment guide](../README.md), including having a running Kubernetes cluster and Helm installed.

## Configuration for LoadBalancer Deployment

The key to this setup lies in the `demo-lb-values.yaml` file, which contains specific parameters to enable and configure external access.

### Key Configuration Parameters

1.  **`externalAccess.enabled`**:
    This is the primary switch to enable the creation of services for external access.
    ```yaml
    externalAccess:
      enabled: true
    ```

2.  **`externalAccess.autoDiscovery.enabled`**:
    When set to `true`, this feature automatically uses the LoadBalancer's external IP/DNS as the advertised address for brokers, making client connection straightforward.
    ```yaml
    autoDiscovery:
      enabled: true
    ```

3.  **`externalAccess.controller.service.loadBalancerAnnotations`** and **`externalAccess.broker.service.loadBalancerAnnotations`**:
    These annotations configure the cloud provider's load balancer. The example below is for provisioning a Network Load Balancer (NLB) on AWS.
    ```yaml
    externalAccess:
      controller:
        service:
          loadBalancerAnnotations:
            - service.beta.kubernetes.io/aws-load-balancer-type: nlb
      broker:
        service:
          loadBalancerAnnotations:
            - service.beta.kubernetes.io/aws-load-balancer-type: nlb
    ```

4.  **`rbac.create`**:
    Required by the `autoDiscovery` feature to grant the necessary permissions for querying service information from the Kubernetes API.
    ```yaml
    rbac:
      create: true
    ```

5.  **`automountServiceAccountToken`**:
    Set to `true` for both the controller and broker, this ensures that the pods mount the service account token. This is necessary for them to authenticate with the Kubernetes API and use the permissions granted by the RBAC rules, which is a prerequisite for the `autoDiscovery` feature to work.
    ```yaml
    controller:
      automountServiceAccountToken: true
    broker:
      automountServiceAccountToken: true
    ```

6.  **`externalAccess.controller.service.ports.external`** and **`externalAccess.broker.service.ports.external`**:
    This sets the external port for the services. While the default is `9094`, this configuration changes it to `9095` for both the controller and broker external services.
    ```yaml
    externalAccess: 
      controller:
        service:
          ports:
            external: 9095
      broker:
        service:
          ports:
            external: 9095
    ```

## Deployment Steps

### 1. Customize `demo-lb-values.yaml`

Before deploying, you must edit the `demo-lb-values.yaml` file to match your environment.

**Action**:

Open `lb/demo-lb-values.yaml` and replace the placeholder values for your S3 buckets (`${ops-bucket}`, `${data-bucket}`), region, and endpoint.

### 2. Install the Helm Chart

Once the values file is configured, deploy AutoMQ. 

**Action**:

From the `kubernetes` directory (the parent directory of `lb`), run the following command:

```shell
helm install automq-lb oci://registry-1.docker.io/bitnamicharts/kafka \
  -f demo-lb-values.yaml \
  --version 31.5.0 \
  --namespace automq \
  --create-namespace
```

## Connect and Test the Cluster

After the installation is complete, it may take a few minutes for the cloud provider to provision the LoadBalancer and assign it a public DNS name.

1.  **Find the External Address**:
    Run the following command and wait for the `EXTERNAL-IP` to be assigned. You will have a different external IP for each Kafka broker. You can get the list of external IPs using the command below:
    ```shell
    kubectl get svc --namespace automq -l "app.kubernetes.io/instance=automq-lb,pod" -w
    ```

2.  **Test with a Kafka Client**:
    Once the `EXTERNAL-IP` is available, use it as the `--bootstrap-server` for your Kafka clients.
    Port `9095` is used for external access, as specified in the `demo-lb-values.yaml` file.
    ```shell
    # Replace <EXTERNAL-IP> with the address from the previous step
    ./kafka-console-producer.sh \
      --bootstrap-server <EXTERNAL-IP>:9095 \
      --topic test-lb \
      --producer.config client.properties
    ```

## Cleanup

To remove the resources created in this guide, uninstall the Helm release. This will also de-provision the LoadBalancer.

```shell
helm uninstall automq-lb --namespace automq
```