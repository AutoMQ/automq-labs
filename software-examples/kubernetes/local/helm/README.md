# AutoMQ Local Quick Start (Kubernetes + MinIO)

This guide provides a quick start for deploying AutoMQ on a local Kubernetes cluster using MinIO as the object storage backend.

> **Platform Support**: Tested on macOS and Linux. Windows users should use WSL2.

## Prerequisites

- Kubernetes cluster (minikube, kind, Docker Desktop, or similar)
- kubectl CLI configured to access your cluster
- Helm 3.x installed
- Internet access for pulling container images

## Quick Start (One-Click Installation)

Run the installation script to deploy AutoMQ with MinIO:

```bash
./install.sh
```

The script will display real-time progress and configuration details:

1. **Prerequisites Check** - Validates kubectl, helm, and cluster connectivity
2. **Configuration Generation** - Detects CPU architecture and generates `automq-values.yaml`
3. **MinIO Installation** - Deploys MinIO as object storage backend
4. **AutoMQ Installation** - Deploys AutoMQ with 3 controller replicas
5. **Verification** - Confirms all pods are running

## Verify Installation

After installation, verify the cluster is working properly:

```bash
./verify.sh
```

This script will:
- Check all AutoMQ pods are running
- Create a test topic (`test-topic`)
- List all topics in the cluster

You can also manually test with kafka commands:

```bash
# Create a topic
kubectl run kafka-client --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \
  kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
  --create --topic my-topic --partitions 3 --replication-factor 1

# List topics
kubectl run kafka-list --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \
  kafka-topics --bootstrap-server automq-automq-enterprise-controller-headless:9092 --list

# Produce messages
kubectl run kafka-producer --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \
  kafka-console-producer --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
  --topic my-topic

# Consume messages
kubectl run kafka-consumer --rm -it --restart=Never --image=confluentinc/cp-kafka:latest -- \
  kafka-console-consumer --bootstrap-server automq-automq-enterprise-controller-headless:9092 \
  --topic my-topic --from-beginning
```

## Cleanup

Remove AutoMQ and MinIO from your cluster:

```bash
./cleanup.sh
```

This script will:
- Uninstall AutoMQ helm release
- Remove AutoMQ PVCs
- Uninstall MinIO helm release
- Remove MinIO PVCs
- Delete generated `automq-values.yaml` file

## Default Configuration

| Component | Setting | Value |
|-----------|---------|-------|
| MinIO | Root User | admin |
| MinIO | Root Password | automq_demo_secret |
| MinIO | Data Bucket | automq-data |
| MinIO | Ops Bucket | automq-ops |
| MinIO | Mode | standalone |
| AutoMQ | Version | 5.3.4 |
| AutoMQ | Controller Replicas | 3 |
| AutoMQ | Controller Memory | 2Gi - 4Gi |
| AutoMQ | Controller CPU | 1 - 2 cores |
| AutoMQ | Heap Size | 2GB |

## Customization

After running `install.sh`, you can edit `automq-values.yaml` and upgrade:

```bash
helm upgrade automq oci://automq.azurecr.io/helm/automq-enterprise-chart \
  --version 5.3.4 \
  -f automq-values.yaml
```

For all available Helm Chart values and configuration options, see:

👉 [Helm Chart Values Reference](https://www.automq.com/docs/automq-cloud/appendix/helm-chart-values-readme)

## Troubleshooting

### Pods not starting

Check pod status and events:

```bash
kubectl get pods -l app.kubernetes.io/name=automq-enterprise
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### MinIO connection issues

Verify MinIO service is accessible:

```bash
kubectl get svc minio
kubectl run test-minio --rm -it --restart=Never --image=busybox -- \
  wget -qO- http://minio.default.svc.cluster.local:9000/minio/health/live
```

### Insufficient resources

For local development, ensure your Kubernetes cluster has adequate resources:
- Minimum 4 CPU cores
- Minimum 8GB RAM

## Production Deployment

This quick start uses MinIO for local testing. For production deployments:

- **Cloud Object Storage**: Replace MinIO with AWS S3, Azure Blob Storage, GCP Cloud Storage, OCI Object Storage, or other S3-compatible storage
- **Cloud Kubernetes**: Deploy on EKS, AKS, GKE, or OKE with proper StorageClass and IAM configurations
- **Resources**: Recommend 4 CPU cores and 16GB memory per AutoMQ Pod
- **WAL Mode**: Consider EBSWAL mode for <10ms latency (requires cloud EBS volumes)

For detailed production deployment instructions including credentials setup, StorageClass configuration, and advanced features (TLS, authentication, auto-scaling), please refer to the official documentation:

👉 [Deploy AutoMQ Software Via Helm Chart](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart)

## Support

- [AutoMQ Documentation](https://docs.automq.com)
- [GitHub Issues](https://github.com/AutoMQ/automq/issues)
