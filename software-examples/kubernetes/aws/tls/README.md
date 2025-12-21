# Deploying AutoMQ on AWS EKS with TLS Encryption

This guide provides two distinct, independent paths for deploying a secure AutoMQ cluster on AWS EKS:

1.  **Path 1: SSL (mTLS)** - Clients authenticate using mutually verified TLS certificates.
2.  **Path 2: SASL_SSL** - Clients authenticate using a username and password, with the connection encrypted by TLS.

Choose the path that best fits your security requirements. The steps for each path are self-contained.

## Prerequisites

- An operational AWS EKS cluster.
- `helm` CLI installed.
- `kubectl` CLI installed and configured to connect to your EKS cluster.
- A set of pre-signed, PEM-formatted TLS certificates obtained from your organization or a CA.
- A private hosted zone in AWS Route 53 for creating DNS records.

---

## Path 1: Configure with SSL (mTLS)

In this path, clients authenticate using their own unique certificate. Administration is also performed using a designated admin certificate.

### Step 1.1: Prepare Certificates

For mTLS, you need certificates for the server, an admin client, and an application client.

- **Required Files:**
    - `ca.crt`: The root CA.
    - `server.crt` / `server.key`: For the server (SAN must include `*.automq.private`).
    - `admin.crt` / `admin.key`: For the administrator. The certificate CN **must be** `automq-admin`.
    - `myapp.crt` / `myapp.key`: For the application. The certificate CN **must be** `my-app`.

### Step 1.2: Create Server TLS Secret

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

### Step 1.3: Configure and Deploy AutoMQ

Use the `values-ssl-mtls.yaml` file provided in this directory. It configures an `SSL` listener and sets the certificate principal `CN=automq-server` as the superuser.

**Before deploying, review `values-ssl-mtls.yaml` and update placeholders.**

Then, deploy the chart:
```bash
helm upgrade --install automq-mtls oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f values-ssl-mtls.yaml \
  --version 5.3.3 \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 1.4: Publish the bootstrap DNS record

You have two options for binding the Route 53 record to the NLB.

**Option A – Automatic (recommended)**

1. Install [external-dns](https://github.com/kubernetes-sigs/external-dns) in your cluster with `--source=service --provider=aws --policy=upsert-only --registry=txt`. Bind its ServiceAccount to an IAM role that can call `route53:ListHostedZones`, `route53:ListResourceRecordSets`, and `route53:ChangeResourceRecordSets`. This section assumes the controller Service already runs as an AWS NLB (using the default AWS VPC CNI or equivalent networking).
2. Configure both the listener’s `advertisedHostnames` block and the controller Service DNS block so they reference the same hosted zone:
   ```yaml
   listeners:
     client:
       - name: CLIENT_SASL_SSL
         containerPort: 9112
         protocol: SASL_SSL
         advertisedHostnames:
           enabled: true
           baseDomain: automq.private
           externalDns:
             privateZoneId: <your-route53-zone-id>

   externalAccess:
     controller:
       enabled: true
       service:
         type: LoadBalancer
       externalDns:
         enabled: true
         hostname: automq-bootstrap.automq.private
         privateZoneId: <your-route53-zone-id>
         recordType: A
         ttl: 60
   ```
3. Redeploy (or `helm upgrade`) so the controller Service renders the annotations. After the Service obtains an NLB hostname, run `kubectl logs -n kube-system deploy/external-dns | grep automq-bootstrap` to confirm external-dns created `automq-bootstrap.automq.private` automatically.

**Option B – Manual fallback**

1.  Get the Load Balancer Hostname:
    ```bash
    kubectl get svc automq-release-automq-enterprise-controller-loadbalancer -n automq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    ```
2.  Create a CNAME (or Alias A) record in Route 53 pointing `loadbalancer.automq.private` (or whatever hostname you used under `externalAccess.controller.externalDns.hostname`) to the hostname from step 1. If you prefer manual control, leave `externalAccess.controller.externalDns.enabled=false` so the Service renders no annotations.

### Step 1.5: Grant ACLs and Test Client

1.  **Create Admin & Client Properties:**
    - `admin.properties`: For the `admin` superuser, using its certificate.
    - `client.properties`: For the `my-app` application user, using its certificate.

    ```bash
    cat /path/to/admin-key.pem /path/to/admin-cert.pem > /path/to/admin-keystore.pem
    ```

    ```properties
    # admin.properties
    security.protocol=SSL
    ssl.truststore.type=PEM
    ssl.truststore.location=/path/to/ca-cert.pem
    ssl.keystore.type=PEM
    ssl.keystore.location=/path/to/admin-keystore.pem
    ssl.endpoint.identification.algorithm=https
    ```

    ```bash
    cat /path/to/user-key.pem /path/to/user-cert.pem > /path/to/user-keystore.pem
    ```

    ```properties
    # client.properties
    security.protocol=SSL
    ssl.truststore.type=PEM
    ssl.truststore.location=/path/to/ca-cert.pem
    ssl.keystore.type=PEM
    ssl.keystore.location=/path/to/user-keystore.pem
    ssl.endpoint.identification.algorithm=https
    ```

2.  **Grant ACLs as Superuser:**
    ```bash
    BOOTSTRAP_SERVER="loadbalancer.automq.private:9122"
    
    # Create a topic
    kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config admin.properties \
      --create --topic mtls-test --partitions 1
    
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

---

## Path 2: Configure with SASL_SSL

In this path, clients authenticate using a username and password. The connection is encrypted, but clients are not required to present their own certificate for authentication.

### Step 2.1: Prepare Certificates

For a SASL_SSL setup, the cluster only needs a server certificate to prove its identity to clients. Clients will need the CA certificate to trust the server.

- **Required Files:**
    - `ca.crt`: The CA certificate clients will use to trust the server.
    - `server.crt`: The server certificate. Its Subject Alternative Name (SAN) list must include a wildcard like `*.automq.private`.
    - `server.key`: The server's private key.

### Step 2.2: Create Server TLS Secret

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

### Step 2.3: Configure and Deploy AutoMQ

Use the `values-sasl-ssl.yaml` file provided in this directory. It configures a `SASL_SSL` listener, sets `admin` as the SASL superuser. Only the controller Service is exposed via an AWS NLB; clients must be able to reach that private NLB endpoint (for example via VPC peering or the same VPC). Broker Services remain internal.

**Before deploying, review `values-sasl-ssl.yaml` and update the following placeholders:**
- `<your-unique-instance-id>`
- `<your-eks-role-arn>`
- `<your-s3-buckets-and-region>`
- `<your-route53-zone-id>`
- `<your-sasl-password>` for `_automq` and `admin`
- `<your_multi_az_subnet_ids>` split by commas (only needed if you add AWS-specific annotations)
- `automq-bootstrap.automq.private` (the controller bootstrap hostname) and `automq.private` (the advertised base domain) can be changed to fit your Route 53 zone naming conventions.

Then, deploy the chart:
```bash
helm upgrade --install automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f values-sasl-ssl.yaml \
  --version 5.3.3 \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 2.4: Publish the bootstrap DNS record

Same as Step 1.4: external access is only required for the controller Service, so reuse the automatic/manual options above.

### Step 2.5: Grant ACLs and Test Client

1.  **Create Admin Properties:**
    - `admin.properties`: For the `admin` client to manage ACLs.

    ```bash
    cat /path/to/admin-key.pem /path/to/admin-cert.pem > /path/to/admin-keystore.pem
    ```

    ```properties
    # admin.properties
    security.protocol=SASL_SSL
    sasl.mechanism=PLAIN
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="admin" password="<your-sasl-password>";
    ssl.truststore.location=/path/to/ca-cert.pem
    ssl.truststore.type=PEM
    ssl.endpoint.identification.algorithm=https
    ```


2.  **Grant ACLs as Superuser:**
    ```bash
    BOOTSTRAP_SERVER="loadbalancer.automq.private:9112"
    
    # Create a topic
    kafka-topics.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config admin.properties \
      --create --topic sasl-test --partitions 1
    
    # Set up SCRAM credentials for 'my-user'
    kafka-configs.sh --bootstrap-server $BOOTSTRAP_SERVER --alter --add-config 'SCRAM-SHA-256=[iterations=8192,password=<your-sasl-password>]'  \
      --entity-type users --entity-name my-user --command-config admin.properties
    
    # Grant permissions to the regular user 'my-user'
    kafka-acls.sh --bootstrap-server $BOOTSTRAP_SERVER --command-config admin.properties \
      --add --allow-principal User:my-user --operation All --topic-pattern-type literal --topic sasl-test
    ```

3.  **Create Admin Properties:**
    - `client.properties`: For the regular user `my-user` to produce/consume.

    ```bash
    cat /path/to/user-key.pem /path/to/user-cert.pem > /path/to/user-keystore.pem
    ```

    ```properties
    # client.properties
    security.protocol=SASL_SSL
    sasl.mechanism=SCRAM-SHA-256
    sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username="my-user" password="<your-sasl-password>";
    ssl.truststore.location=/path/to/ca-cert.pem
    ssl.truststore.type=PEM
    ssl.endpoint.identification.algorithm=https
    ```

4.  **Test as Regular User:**
    ```bash
    # Test with my-user credentials
    kafka-console-producer.sh --bootstrap-server $BOOTSTRAP_SERVER \
      --producer.config client.properties --topic sasl-test
    > Hello SASL!
    > ^C
    ```

## Cleanup

To remove the resources from either path, uninstall the Helm release and delete the associated secrets and DNS records. For example, for the mTLS path:

```bash
helm uninstall automq-mtls --namespace <your-namespace>
kubectl delete secret automq-server-tls --namespace <your-namespace>
# Remember to delete the CNAME record in Route 53.
```
