# Best Practice Guide for AutoMQ Enterprise on AWS Kubernetes

This demo summarizes the best practice for deploying AutoMQ Enterprise version on AWS EKS, focusing on the following key features:

- **Pod Authorization**: Based on IRSA's least privilege control, avoid storing long-term credentials in Pods.
- **S3 WAL**: Use S3 for WAL storage to achieve fully diskless architecture.
- **Multi-Available Zone**: The cluster is deployed across AZs simultaneously to ensure availability zone-level resilience.
- **mTLS Authentication**: Use standardized PEM/JKS certificates to secure communication between clients and brokers, as well as between brokers.
- **External Access**: Exposes the cluster endpoint through an AWS NLB for external access to the Kubernetes cluster. Only a single NLB is required for bootstrap; there's no need to assign separate NLBs to each broker.

---

## 1. Preparatory Work

1. **Kubernetes Cluster** (Recommended to git clone locally and use the template in the [ Terraform guide for AWS EKS ](https://github.com/AutoMQ/automq-labs/blob/main/byoc-examples/setup/kubernetes/aws/terraform/README.md) documentation).
   If it is a custom deployment, the following conditions must be met:

   - Has installed `AWS Load Balancer Controller`, `external-dns` and `CSI Driver`;
   - Key components (AutoMQ Pods, Kubernetes cluster plugins, etc.) all obtain permissions based on IAM for Service Account (IRSA);
     - For specific required permissions, please refer to the [IRSA](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) document description and associate with necessary [ policy.json ](policy.json) .
   - Memory-optimized instances (such as `c6g.2xlarge`, `r6in.large`) are recommended for working nodes, and they should be distributed across at least 3 Available Zones.
2. **Helm CLI**: version ≥ v3.6.0。
3. **TLS Certificate**: Prepare a set of PEM or JKS certificates (including at least `ca.crt`, `tls.crt`, `tls.key`), issued by an enterprise CA or a trusted third party.
4. **Route 53 Private Hosted Zone**: Used to resolve the corresponding domain names in `bootstrap.servers`, `advertised.listener`.

   - PS: The subsequent parts of the article will all use `automq.private` as an example for Domain

---

## 2. Deployment Steps

### 2.1 Create Namespace

```
kubectl create namespace automq
```

### 2.2 Create TLS Secret

1. Prepare AutoMQ Server CSR to generate certificates/keys

```
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = automq-server

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.automq.private
...
```

> - Extension key (extendedKeyUsage) usages are relevant for client and server authentication. AutoMQ server brokers require both client and server authentication for intracluster communication because every broker is both the client and the server for the other brokers.
> - SAN needs to use a wildcard domain name and match the domain name corresponding to the Private DNS Zone Id you set in demo-values.yaml, which is used for TLS host domain name verification.

1. Create secret for server TLS

```bash
kubectl create secret generic automq-tls-secret \
  --from-file=kafka-ca.crt=/path/to/ca.crt \
  --from-file=kafka.crt=/path/to/tls.crt \
  --from-file=kafka.key=/path/to/tls.key \
  -n automq
```

### 2.2 Prepare your `demo-values.yaml`

1. Refer to Best Practices `demo-values.yaml`: 
   - [demo-values.yaml](./demo-values.yaml)



2. Using `demo-values.yaml` as a template, replace the following placeholders:

| Category          | Parameters to be replaced                          | Example Explanation                                                                 |
|-------------------|----------------------------------------------------|-------------------------------------------------------------------------------------|
| Authentication    | `<your-eks-role-arn>`                              | Corresponding IRSA Role ARN                                                         |
| Main Storage      | `<your-ops-bucket>`<br/><code>&lt;your-data-bucket&gt;</code><br/><code>&lt;aws-region&gt;</code> | Points to the Ops/Data S3 bucket and the Region it resides in respectively          |
| TLS               | `<your-tls-secret>`                                | Server TLS Secret Name                                                              |
| Listener DNS      | `<your-route53-zone-domain>`<br/><code>&lt;your-route53-zone-id&gt;</code> | Determine your listener:<br/>- Hosted Zone ID<br/>- Hosted Zone Domain e.g.: `automq.private` |
| External access   | `<your-bootstrap-server-hostname>`                 | Determine your bootstrap-server domain name.<br/>e.g.: `bootstrap.automq.private`   |
| Multi-AZ          | `<your_multi_az_subnet_ids>`                       | Comma-separated list of Subnet IDs, corresponding to multiple private subnets of your node group |

> Observability tip: when editing `demo-values.yaml`, you can enable pull-based Prometheus scraping or OTLP push (via Collector/Remote Write) by setting the `s3.telemetry.metrics.exporter.*` keys under `global.config`. For example:
> ```yaml
> global:
>   config: |
>     s3.telemetry.metrics.exporter.type=prometheus,otlp
>     s3.telemetry.metrics.exporter.uri=prometheus://?host=0.0.0.0&port=9090,otlp://?endpoint=http://otel-collector.monitoring:4317&protocol=grpc
>     s3.telemetry.metrics.base.labels=instance.id=<your-automq-instance-id>
> ```
> See the [Integrating Metrics with Prometheus guide](https://www.automq.com/docs/automq/observability/integrating-metrics-with-prometheus) for more details.

### 2.3 Install AutoMQ Enterprise

```bash
helm install automq-release oci://automq.azurecr.io/helm/automq-enterprise-chart \
  -f ./demo-values.yaml \
  --version 5.3.2 \
  --namespace automq \
  --create-namespace
```

### 2.4 Verification Deployment

Ensure the controller/broker pods is Ready:

```
kubectl get pods -n automq -w
```

```sql
NAME                                            READY   STATUS    RESTARTS   AGE
automq-release-automq-enterprise-broker-0       1/1     Running   0          6m
automq-release-automq-enterprise-controller-0   1/1     Running   0          5m59s
automq-release-automq-enterprise-controller-1   1/1     Running   0          5m59s
automq-release-automq-enterprise-controller-2   1/1     Running   0          5m59s
```

Once the cluster is ready, access it using the endpoint `bootstrap.automq.private` or your custom hostname.

---

## 3. Usage and Testing

### 3.1 Client Certificates and Configuration

Use the corresponding CSR to generate certificates/keys for your superuser and regular users respectively.

1. Admin CSR

```
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = admin

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.automq.private
```

> In Admin CSR:
>
> - CN must match the name of the Admin superuser you set in demo-values.yaml.
> - SAN needs to use a wildcard domain name and match the domain name corresponding to the Private DNS Zone Id you set in demo-values.yaml, which is used for TLS host domain name verification.

2. Common User CSR

```
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = my-app

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.automq.private
```

> In User CSR:
>
> - CN needs to correspond to the name of the User subsequently authorized by ACL
> - SAN also needs to match your Private DNS Zone for TLS host domain name verification

3. Client separately configures `admin-ssl.properties`, specifying certificate/key paths for Admin user respectively

```bash
cat /path/to/admin-key.pem /path/to/admin-cert.pem > /path/to/admin-keystore.pem
```

```bash
vim admin-ssl.properties
```

```
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/ca-cert.pem
ssl.keystore.type=PEM
ssl.keystore.location=/path/to/admin-keystore.pem
ssl.endpoint.identification.algorithm=https
```

4. Client separately configures `user-ssl.properties`, specifying certificate/key paths for regular users respectively

```bash
cat /path/to/user-key.pem /path/to/user-cert.pem > /path/to/user-keystore.pem
```

```bash
vim user-ssl.properties
```

```
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=/path/to/ca-cert.pem
ssl.keystore.type=PEM
ssl.keystore.location=/path/to/user-keystore.pem
ssl.endpoint.identification.algorithm=https
```


### 3.2 ACL Authorization

Execute `kafka-acls.sh` as the superuser to add application principals such as `User:CN=my-app` to the allow list of the corresponding Topic/Group:

```bash
kafka-acls.sh --bootstrap-server bootstrap.automq.private:9122 \
  --command-config admin-ssl.properties \
  --add --allow-principal "User:CN=my-app" \
  --operation All --topic my-topic

kafka-acls.sh --bootstrap-server bootstrap.automq.private:9122 \
  --command-config admin-ssl.properties \
  --add --allow-principal "User:CN=my-app" \
  --operation All --group "*" --resource-pattern-type LITERAL
```

### 3.3 Create a Topic and verify sending and receiving

```bash
# create topic
def BOOTSTRAP=bootstrap.automq.private:9122
kafka-topics.sh --create --bootstrap-server $BOOTSTRAP \
  --topic my-topic --partitions 3 \
  --command-config user-ssl.properties

# produce message
kafka-console-producer.sh --bootstrap-server $BOOTSTRAP \
  --topic my-topic --producer.config user-ssl.properties

# consume message
kafka-console-consumer.sh --bootstrap-server $BOOTSTRAP \
  --topic my-topic --consumer.config user-ssl.properties \
  --from-beginning
```

If the external Client can complete sending and receiving through the above commands, it indicates that all configurations such as mTLS, ACL, and Route 53 automatic binding have taken effect.

---

For a more in-depth parameter description, please refer to the detailed configuration section in the [AutoMQ Helm Chart official documentation](https://www.automq.com/docs/automq-cloud/appendix/helm-chart-values-readme), or refer to the advanced example in `automq-labs/software/kubernetes/aws/tls/README.md`. Wish you a smooth deployment!
