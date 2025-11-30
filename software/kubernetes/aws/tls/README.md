# Deploying AutoMQ on AWS EKS with TLS Encryption

This guide provides two distinct, independent paths for deploying a secure AutoMQ cluster on AWS EKS:

1.  **Path 1: SASL_SSL** - Clients authenticate using a username and password, with the connection encrypted by TLS.
2.  **Path 2: SSL (mTLS)** - Clients authenticate using mutually verified TLS certificates.

Choose the path that best fits your security requirements. The steps for each path are self-contained.

## Prerequisites

- An operational AWS EKS cluster.
- `helm` CLI installed.
- `kubectl` CLI installed and configured to connect to your EKS cluster.
- A set of pre-signed, PEM-formatted TLS certificates obtained from your organization or a CA.
- A private hosted zone in AWS Route 53 for creating DNS records.

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

You only need this single PEM bundle. During pod startup AutoMQ automatically converts it into the keystore/truststore files consumed by **all** broker/controller listeners and by the internal `automq.admin.*` clients (AutoBalancer, admin utilities, inter-controller RPCs). No extra client-specific secret is required.

</Tip>

### Step 1.3: Configure and Deploy AutoMQ

Use the `values-sasl-ssl.yaml` file provided in this directory. It configures a `SASL_SSL` listener, sets `_automq` as the SASL superuser, and defines a regular SASL user `my-user`.

**Before deploying, review `values-sasl-ssl.yaml` and update the following placeholders:**
- `<your-unique-instance-id>`
- `<your-eks-role-arn>`
- `<your-s3-buckets-and-region>`
- `<your-route53-zone-id>`
- `<your-sasl-password>` for both `_automq` and `my-user`
- `<your_multi_az_subnet_ids>` split by commas

Then, deploy the chart:
```bash
helm upgrade --install automq-release oci://automq.azurecr.io/helm/automq-enterprise \
  -f values-sasl-ssl.yaml \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 1.4: Publish the bootstrap DNS record

You have two options for binding the Route 53 record to the NLB.

**Option A – Automatic (recommended)**

1. Install [external-dns](https://github.com/kubernetes-sigs/external-dns) in your cluster with `--source=service --provider=aws --policy=upsert-only --registry=txt`. Bind its ServiceAccount to an IAM role that can call `route53:ListHostedZones`, `route53:ListResourceRecordSets`, and `route53:ChangeResourceRecordSets`.
2. Ensure the hosted zone domain matches your `values-sasl-ssl.yaml`:
   ```yaml
   externalAccess:
     loadBalancer:
       domain: automq.private          # must equal the Route 53 hosted zone domain
       bootstrapPrefix: automq-bootstrap
       externalDns:
         enabled: true
         targetService: controller
         listenerKey: client_mtls      # resolves automq.dns.client_mtls.zone.id from global.config
         recordType: CNAME             # switch to A if you prefer an Alias
         ttl: 60
   global:
     config: |
       automq.dns.client_mtls.zone.id=<your_hosted_zone_id>
   ```
3. Redeploy (or `helm upgrade`) so the controller Service renders the annotations. After the Service obtains an NLB hostname, run `kubectl logs -n kube-system deploy/external-dns | grep automq-bootstrap` to confirm external-dns created `automq-bootstrap.automq.private` automatically.

**Option B – Manual fallback**

1.  Get the Load Balancer Hostname:
    ```bash
    kubectl get svc automq-release-automq-enterprise-controller-loadbalancer -n automq -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    ```
2.  Create a CNAME (or Alias A) record in Route 53 pointing `loadbalancer.automq.private` to the hostname from step 1.

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

AutoMQ reuses this secret for its internal clients as well; the chart converts it into keystore/truststore files under `/opt/automq/kafka/config/certs/` and wires them into the `automq.admin.*` configuration with hostname verification disabled so the control plane can connect via Pod IPs. You only need to manage this one secret even in mTLS mode.

</Tip>

### Step 2.3: Configure and Deploy AutoMQ

Use the `values-ssl-mtls.yaml` file provided in this directory. It configures an `SSL` listener and sets the certificate principal `User:automq-admin` as the superuser.

**Before deploying, review `values-ssl-mtls.yaml` and update placeholders.**

Then, deploy the chart:
```bash
helm upgrade --install automq-mtls oci://automq.azurecr.io/helm/automq-enterprise \
  -f values-ssl-mtls.yaml \
  --namespace <your-namespace> \
  --create-namespace
```

### Step 2.4: Publish the bootstrap DNS record

You can reuse the automatic/manual options described in Step 1.4. If both SASL_SSL and mTLS clusters share the same Route 53 hosted zone, make sure each cluster uses a unique `bootstrapPrefix` (for example `sasl-bootstrap` vs `mtls-bootstrap`) so external-dns writes distinct records.

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
# Remember to delete the CNAME record in Route 53.
```
