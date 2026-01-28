# AutoMQ Software Quick Start (Docker Compose + MinIO)

This guide provides a quick start for deploying AutoMQ Software on your local machine using Docker Compose with MinIO as the object storage backend.

> **Platform Support**: Tested on macOS and Linux. Windows users should use WSL2.

## Prerequisites

- Docker Engine 20.10+ with Docker Compose V2
- Minimum 4 CPU cores and 8GB RAM available for Docker
- Internet access for pulling container images
- Access to AutoMQ Software container registry

## Quick Start (One-Click Installation)

Run the installation script to deploy AutoMQ with MinIO:

```bash
./install.sh
```

The script will display real-time progress and configuration details:

1. **Prerequisites Check** - Validates Docker and Docker Compose installation
2. **Image Pull** - Downloads required container images
3. **Cluster Startup** - Launches MinIO and 3 AutoMQ controller nodes
4. **Health Check** - Confirms all services are running

## Verify Installation

After installation, verify the cluster is working properly:

```bash
./verify.sh
```

This script will:
- Check all AutoMQ containers are running
- Verify MinIO buckets are created
- Create a test topic (`test-topic`)
- List all topics in the cluster

### Manual Verification

You can also manually test with Kafka commands:

```bash
# Create a topic
docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh \
  --bootstrap-server controller1:9092 \
  --create --topic my-topic --partitions 3 --replication-factor 1

# List topics
docker exec automq-controller1 /opt/automq/kafka/bin/kafka-topics.sh \
  --bootstrap-server controller1:9092 --list

# Produce messages (interactive)
docker exec -it automq-controller1 /opt/automq/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server controller1:9092 --topic my-topic

# Consume messages
docker exec -it automq-controller1 /opt/automq/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server controller1:9092 --topic my-topic --from-beginning
```

### External Client Access

Connect from your host machine using the external bootstrap servers:

```bash
# Using kafka-cli or any Kafka client
kafka-topics.sh --bootstrap-server localhost:19092,localhost:29092,localhost:39092 --list
```

## Cleanup

Remove AutoMQ and MinIO from your system:

```bash
./cleanup.sh
```

This script will:
- Stop and remove all AutoMQ containers
- Remove MinIO container and data
- Clean up Docker network
- Remove associated volumes

## Default Configuration

| Component | Setting | Value |
|-----------|---------|-------|
| MinIO | Root User | admin |
| MinIO | Root Password | automq_demo_secret |
| MinIO | Data Bucket | automq-data |
| MinIO | Ops Bucket | automq-ops |
| MinIO | API Port | 9000 |
| MinIO | Console Port | 9001 |
| AutoMQ | Version | 5.3.7 |
| AutoMQ | Controller Replicas | 3 |
| AutoMQ | Heap Size | 1GB - 4GB |
| AutoMQ | External Ports | 19092, 29092, 39092 |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Network                            │
│                        (automq_net)                              │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │ controller1 │  │ controller2 │  │ controller3 │              │
│  │  (node 0)   │  │  (node 1)   │  │  (node 2)   │              │
│  │  :19092     │  │  :29092     │  │  :39092     │              │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘              │
│         │                │                │                      │
│         └────────────────┼────────────────┘                      │
│                          │                                       │
│                    ┌─────┴─────┐                                 │
│                    │   MinIO   │                                 │
│                    │  :9000    │                                 │
│                    │  :9001    │                                 │
│                    └───────────┘                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Customization

### Modify Cluster Configuration

Edit `docker-compose.yaml` to customize:

- **Heap Size**: Adjust `KAFKA_HEAP_OPTS` in the common environment variables
- **Node Count**: Add or remove controller services
- **Ports**: Change external port mappings
- **Storage**: Configure different S3 endpoints or credentials

### Generate New Cluster ID

```bash
# Generate a new unique cluster ID
docker run --rm automq.azurecr.io/automq/automq-enterprise:5.3.7 \
  /opt/automq/kafka/bin/kafka-storage.sh random-uuid
```

Update the `CLUSTER_ID` in `docker-compose.yaml` with the generated value.

## Troubleshooting

### Containers not starting

Check container status and logs:

```bash
# View all container status
docker compose ps

# Check specific container logs
docker compose logs controller1
docker compose logs minio

# Follow logs in real-time
docker compose logs -f
```

### MinIO connection issues

Verify MinIO is healthy:

```bash
# Check MinIO health
curl -f http://localhost:9000/minio/health/live

# Access MinIO Console
open http://localhost:9001
```

### Port conflicts

If ports are already in use, modify the port mappings in `docker-compose.yaml`:

```yaml
ports:
  - "19092:9092"  # Change 19092 to an available port
```

### Insufficient resources

Ensure Docker has adequate resources allocated:
- Minimum 4 CPU cores
- Minimum 8GB RAM
- Sufficient disk space for container images and data

## Production Deployment

This quick start uses MinIO for local testing. For production deployments:

- **Cloud Object Storage**: Replace MinIO with AWS S3, Azure Blob Storage, GCP Cloud Storage, or other S3-compatible storage
- **Container Orchestration**: Consider Kubernetes with Helm charts for production-grade deployments
- **Resources**: Recommend 4 CPU cores and 16GB memory per AutoMQ node
- **High Availability**: Deploy across multiple availability zones
- **Security**: Enable TLS, authentication, and proper network isolation

For detailed production deployment instructions, please refer to the official documentation:

👉 [AutoMQ Software Documentation](https://www.automq.com/docs/automq-cloud/appendix/deploy-automq-enterprise-via-helm-chart)

## Support

- [AutoMQ Documentation](https://docs.automq.com)
- [GitHub Issues](https://github.com/AutoMQ/automq/issues)
