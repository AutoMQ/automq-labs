# Deploying AutoMQ on OCI OKE with TLS Encryption

This guide provides two distinct, independent paths for deploying a secure AutoMQ cluster on OCI OKE:

1.  **Path 1: SASL_SSL** - Clients authenticate using a username and password, with the connection encrypted by TLS.
2.  **Path 2: SSL (mTLS)** - Clients authenticate using mutually verified TLS certificates.

Choose the path that best fits your security requirements. The steps for each path are self-contained.

## Prerequisites

- An operational OCI OKE cluster.
- `helm` CLI installed.
- `kubectl` CLI installed and configured to connect to your OKE cluster.
- A set of pre-signed, PEM-formatted TLS certificates obtained from your organization or a CA.
- A private hosted zone in OCI Private DNS for creating DNS records.

---

## Path 1: Configure with SASL_SSL

In this path, clients authenticate using a username and password. The connection is encrypted, but clients are not required to present their own certificate for authentication.

### Step 1.1: Prepare Certificates

For a SASL_SSL setup, the cluster only needs a server certificate to prove its identity to clients. Clients will need the CA certificate to trust the server.

- **Required Files:**
  - `ca.crt`: The CA certificate clients will use to trust the server.
  - `server.crt`: The server certificate. Its Subject Alternative Name (SAN) list must include a wildcard like `*.automq.private`.
  - `server.key`: The server's private key.

### Step 1.2: Create Server TLS Secret

Create a Kubernetes secret to hold the server's certificate materials.

```bash
kubectl create secret generic automq-server-tls \
  --from-file=tls.crt=./server.crt \
  --from-file=tls.key=./server.key \
  --from-file=ca.crt=./ca.crt \
  --namespace <your-namespace>
```

<Tip>

You only need this single PEM bundle. During pod startup AutoMQ mounts the PEM files directly for **all** broker/controller listeners and the internal `automq.admin.*` clients, so no extra client-specific Secret is required.

</Tip>

### Step 1.3: Configure and Deploy AutoMQ

Use the `values-sasl-ssl.yaml` file provided in this directory. It configures a `SASL_SSL` listener, sets `_automq` as the SASL superuser, and defines a regular SASL user `my-user`. Only the controller Service is exposed via an OCI NLB; clients must be able to reach that private NLB endpoint (for example via VPC peering or the same VPC). Broker Services remain internal.

**Before deploying, review `values-sasl-ssl.yaml` and update the following placeholders:**
- `<your-unique-instance-id>`
- `<your-data-bucket>` and `<your-ops-bucket>`
- `<your-sasl-password>` for both `_automq` and `my-user`
- `<your_private_subnet_ocid>` split by commas (only needed if you add OCI-specific annotations)
- `automq-bootstrap.automq.private` (the controller bootstrap hostname) and `automq.private` (the advertised base domain) can be changed to fit your Private DNS zone naming conventions.

Then, deploy the chart:
```bash
helm upgrade --install automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f values-sasl-ssl.yaml \
  --version 5.3.2 \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 1.4: Publish the bootstrap DNS record

**Manual**

1.  Get the Load Balancer Hostname:
    ```bash
    kubectl get svc automq-release-automq-enterprise-controller-loadbalancer -n automq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    ```
2.  Create a A record in Private DNS pointing `loadbalancer.automq.private` (or whatever hostname you used under `externalAccess.controller.externalDns.hostname`) to the hostname from step 1. If you prefer manual control, leave `externalAccess.controller.externalDns.enabled=false` so the Service renders no annotations.

### Step 1.5: Grant ACLs and Test Client

1.  **Create Admin & Client Properties:**
    - `superuser.properties`: For the `_automq` admin to manage ACLs.
    - `client.properties`: For the regular user `my-user` to produce/consume.

    ```properties
    # superuser.properties
    security.protocol=SASL_SSL
    sasl.mechanism=PLAIN
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="_automq" password="<your-sasl-password>";
    ssl.truststore.certificates=/path/to/ca.crt
    ```

    ```properties
    # client.properties
    security.protocol=SASL_SSL
    sasl.mechanism=PLAIN
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="my-user" password="<your-sasl-password>";
    ssl.truststore.certificates=/path/to/ca.crt
    ```

2.  **Grant ACLs as Superuser:**
    ```bash
    BOOTSTRAP_SERVER="loadbalancer.automq.private:9112"
    
    # Create a topic
    kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config superuser.properties \
      --create --topic sasl-test --partitions 1 --replication-factor 1
      
    # Grant permissions to the regular user 'my-user'
    kafka-acls.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config superuser.properties \
      --add --allow-principal User:my-user --operation All --topic-pattern-type literal --topic sasl-test
    ```

3.  **Test as Regular User:**
    ```bash
    # Test with my-user credentials
    kafka-console-producer.sh --bootstrap-server $BOOTSTRAP_SERVER \
      --producer.config client.properties --topic sasl-test
    > Hello SASL!
    > ^C
    ```

---

## Path 2: Configure with SSL (mTLS)

In this path, clients authenticate using their own unique certificate. Administration is also performed using a designated admin certificate.

### Step 2.1: Prepare Certificates

For mTLS, you need certificates for the server, an admin client, and an application client.

- **Required Files:**
  - `ca.crt`: The root CA.
  - `server.crt` / `server.key`: For the server (SAN must include `*.automq.private`).
  - `admin.crt` / `admin.key`: For the administrator. The certificate CN **must be** `automq-admin`.
  - `myapp.crt` / `myapp.key`: For the application. The certificate CN **must be** `my-app`.

### Step 2.2: Create Server TLS Secret

This is the same as in Path 1. The secret provides the server's identity.

```bash
kubectl create secret generic automq-server-tls \
  --from-file=tls.crt=./server.crt \
  --from-file=tls.key=./server.key \
  --from-file=ca.crt=./ca.crt \
  --namespace <your-namespace>
```

<Tip>

AutoMQ mounts the same PEM bundle under `/opt/automq/kafka/config/certs/` and wires it into the `automq.admin.*` configuration (hostname verification disabled so the control plane can talk via Pod IPs), so even in mTLS mode you only manage one Secret.

</Tip>

### Step 2.3: Configure and Deploy AutoMQ

Use the `values-ssl-mtls.yaml` file provided in this directory. It configures an `SSL` listener and sets the certificate principal `User:automq-admin` as the superuser.

**Before deploying, review `values-ssl-mtls.yaml` and update placeholders.**

Then, deploy the chart:
```bash
helm upgrade --install automq-mtls oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f values-ssl-mtls.yaml \
  --version 5.3.2 \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 2.4: Publish the bootstrap DNS record

Same as Step 1.4: external access is only required for the controller Service, so reuse the automatic/manual options above and ensure each cluster uses a unique `bootstrapPrefix`.

### Step 2.5: Grant ACLs and Test Client

1.  **Create Admin & Client Properties:**
    - `admin.properties`: For the `_automq` superuser, using its certificate.
    - `client.properties`: For the `my-app` application user, using its certificate.

    ```properties
    # admin.properties
    security.protocol=SSL
    ssl.truststore.certificates=/path/to/ca.crt
    ssl.keystore.key=/path/to/admin.key
    ssl.keystore.certificate.chain=/path/to/admin.crt
    ```

    ```properties
    # client.properties
    security.protocol=SSL
    ssl.truststore.certificates=/path/to/ca.crt
    ssl.keystore.key=/path/to/myapp.key
    ssl.keystore.certificate.chain=/path/to/myapp.crt
    ```

2.  **Grant ACLs as Superuser:**
    ```bash
    BOOTSTRAP_SERVER="loadbalancer.automq.private:9122"
    
    # Create a topic
    kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config admin.properties \
      --create --topic mtls-test --partitions 1 --replication-factor 1
    
    # Grant permissions to the application principal 'User:my-app'
    kafka-acls.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config admin.properties \
      --add --allow-principal User:my-app --operation All --topic-pattern-type literal --topic mtls-test
    ```

3.  **Test as Regular User:**
    ```bash
    # Test with my-app certificate
    kafka-console-producer.sh --bootstrap-server $BOOTSTRAP_SERVER \
      --producer.config client.properties --topic mtls-test
    > Hello mTLS!
    > ^C
    ```

## Cleanup

To remove the resources from either path, uninstall the Helm release and delete the associated secrets and DNS records. For example, for the mTLS path:

```bash
helm uninstall automq-mtls --namespace <your-namespace>
kubectl delete secret automq-server-tls --namespace <your-namespace>
# Remember to delete the A record in Private DNS.
```
