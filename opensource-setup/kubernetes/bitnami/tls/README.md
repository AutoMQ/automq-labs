# Deploy AutoMQ with mTLS on Kubernetes

This guide provides instructions for setting up a secure AutoMQ cluster with mutual TLS (mTLS) on Kubernetes. It uses helper scripts to automate the generation of certificates and the configuration of a Kafka client for secure communication.

The process involves two main scripts:
1.  `generate_server_certs.sh`: Creates a Certificate Authority (CA) and server-side certificates required by the AutoMQ cluster.
2.  `generate_client_certs.sh`: Generates client-side certificates and a configuration file for a Kafka client to securely connect to the cluster.

## Prerequisites

*   A running Kubernetes cluster with `kubectl` configured.
*   Helm v3 installed.
*   OpenSSL and `keytool` installed on your local machine.

## Step-by-Step Guide

### Step 1: Generate Server Certificates

First, we need to generate the CA and the server certificates that the AutoMQ brokers will use to identify themselves.

1.  Make the server script executable:
    ```bash
    chmod +x generate_server_certs.sh
    ```

2.  Run the script to generate the certificates and create the necessary Kubernetes secrets.
    ```bash
    # Usage: ./generate_server_certs.sh --password <your-password> --namespace <your-namespace> --release-name <helm-release-name>
    ./generate_server_certs.sh \
      --password your-secure-password \
      --namespace automq \
      --release-name automq-release
    ```
    This command creates two Kubernetes secrets (`kafka-tls-secret` and `kafka-tls-passwords`) in the `automq` namespace and leaves `ca-cert` and `ca-key` files in your current directory for the next step.

### Step 2: Deploy AutoMQ with mTLS Enabled

Now, deploy AutoMQ using the Bitnami Helm chart, configured to use the secrets we just created.

1.  **Customize `demo-tls-values.yaml`**:
    Review the provided [demo-tls-values.yaml](demo-tls-values.yaml) file. You must replace the placeholder values for your S3 buckets (`${ops-bucket}`, `${data-bucket}`), region, and endpoint.

2.  **Install the Helm Chart**:
    Deploy AutoMQ using your customized values file. We recommend using a version from the `31.x` series of the Bitnami Kafka chart.
    ```shell
    helm install automq-release oci://registry-1.docker.io/bitnamicharts/kafka \
      -f demo-tls-values.yaml \
      --version 31.5.0 \
      --namespace automq \
      --create-namespace
    ```

### Step 3: Configure and Test the Client

To verify the mTLS setup, we will launch a client pod, generate client certificates for it, and use it to produce and consume messages.

1.  **Launch a Client Pod**:
    Create a simple pod with Kafka tools installed.
    ```bash
    kubectl run kafka-client --image=automqinc/automq:1.6.0-bitnami -n automq --restart='Never' --command -- sleep infinity
    ```

2.  **Generate Client Certificates**:
    Make the client script executable and run it. This script uses the `ca-cert` and `ca-key` from Step 1 to generate client certificates and copies them into the `kafka-client` pod.
    ```bash
    chmod +x generate_client_certs.sh
    # Usage: ./generate_client_certs.sh --password <your-password> --namespace <your-namespace> --pod-name <client-pod-name>
    ./generate_client_certs.sh \
      --password your-secure-password \
      --namespace automq \
      --pod-name kafka-client
    ```

3.  **Produce and Consume Messages**:
    Execute producer and consumer commands from within the client pod to test the secure connection.

    *   **Send messages:**
        ```bash
        kubectl exec -it kafka-client -n automq -- bash -c "
          ./kafka-console-producer.sh \
            --bootstrap-server automq-release-kafka.automq.svc.cluster.local:9092 \
            --producer.config /opt/bitnami/kafka/config/client.properties \
            --topic test-mtls
        "
        ```
        (Type a few messages and press `Ctrl+C` to exit)

    *   **Receive messages:**
        ```bash
        kubectl exec -it kafka-client -n automq -- bash -c "
          ./kafka-console-consumer.sh \
            --bootstrap-server automq-release-kafka.automq.svc.cluster.local:9092 \
            --consumer.config /opt/bitnami/kafka/config/client.properties \
            --topic test-mtls \
            --from-beginning
        "
        ```
    If both commands run without SSL errors, your mTLS setup is working correctly.

## Cleanup

To remove the resources created in this guide, run the following commands:

1.  **Uninstall the Helm release**:
    ```bash
    helm uninstall automq-release --namespace automq
    ```
2.  **Delete the client pod and secrets**:
    ```bash
    kubectl delete pod kafka-client -n automq
    kubectl delete secret kafka-tls-secret kafka-tls-passwords -n automq
    ```
3.  **Remove local certificate files**:
    ```bash
    rm ca-cert ca-key
    ```

## Notes and Troubleshooting

*   **Security**: The `ca-key` file is highly sensitive. Store it securely and remove it once it's no longer needed.
*   **SANs**: The server certificate is generated with Subject Alternative Names (SANs) that match the default Kubernetes service names created by the Helm chart. If you change the release name or replica counts, you may need to adjust the `openssl-san.cnf` section inside the `generate_server_certs.sh` script.
*   **SSL Handshake Errors**: If you encounter SSL errors, double-check that the `--namespace` and `--release-name` used in the scripts and Helm installation match exactly. Also, verify that the client pod is running and accessible.
