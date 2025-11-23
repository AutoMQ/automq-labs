# Deploy AutoMQ with TLS

This document provides a quick guide on how to deploy AutoMQ Enterprise on Kubernetes with TLS enabled, using the provided `demo-tls-values.yaml`.

This example demonstrates a setup for mTLS (mutual TLS), where both the server and client authenticate each other using certificates.

## Prerequisites

- Ensure you have completed all the prerequisites mentioned in the main [deployment guide](../deployment.md).
- You must have your own PEM-formatted server certificate, server private key, and CA certificate.

## Configuration

The `demo-tls-values.yaml` file is pre-configured to enable TLS. The key sections to review are:

- **`global.config`**: Contains TLS-related settings, such as `ssl.truststore.certificates`, `ssl.keystore.key`, and `ssl.keystore.certificate.chain`. You will need to paste your certificate contents directly into these fields as single-line strings.
- **`listeners`**: Overridden to enable `SASL_SSL` listeners for clients.
- **`tls.selfConfigure`**: Set to `true` to let the chart manage TLS setup.
- **`acl` and `sasl`**: Enabled to demonstrate a secure setup.

For a complete explanation of all parameters and security configurations, please refer to the main [deployment guide's security section](../deployment.md#security-and-access-control).

## Installation

1.  **Prepare Certificates**:
    You need to convert your multi-line PEM certificate files into single-line strings with `\n` as newline characters. You can use a command like this:
    ```shell
    awk 'NF {printf "%s\\n", $0;}' your-cert.pem
    ```
    Repeat this for your CA certificate, server certificate, and server private key.

2.  **Update `demo-tls-values.yaml`**:
    Edit the `demo-tls-values.yaml` file and replace all placeholder values (`${...}`), including pasting the single-line certificate strings you just generated.

3.  **Install the Helm Chart**:
    Run the following command to deploy AutoMQ with TLS enabled:
    ```shell
    helm install automq-release oci://automq.azurecr.io/helm/automq-enterprise \
      -f demo-tls-values.yaml \
      --version 5.2.0 \
      --namespace automq \
      --create-namespace
    ```

## Client Connection

To connect to the cluster, your Kafka client will need a `client.properties` file configured with the client-side certificates. For more details, see the [client configuration section in the main deployment guide](../deployment.md#client-configuration-for-tls).
