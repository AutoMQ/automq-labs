# AutoMQ Binary Deployment Quick Start

This guide provides step-by-step instructions for deploying a 3-node AutoMQ cluster using the binary installation package with MinIO as the object storage backend.

> **Note**: This is a quick start guide for local development and testing. For production deployments:
> - Deploy each node on a separate machine with at least 2 CPU cores and 16GB RAM
> - Replace MinIO with a production-grade object storage service (AWS S3, Azure Blob Storage, etc.)
> - Adjust heap size based on workload requirements (default: 2GB per node for testing)

## Prerequisites

- Linux or macOS operating system
- Docker and Docker Compose installed
- Java 17 or later
- At least 8GB available RAM (for running 3 nodes locally)
- Internet access for downloading packages

## Quick Start

### Step 1: Environment Setup

Run the setup script to verify prerequisites, download the installation package, and generate configuration:

```bash
curl -sSL https://raw.githubusercontent.com/AutoMQ/automq-examples/main/software-examples/binary/setup.sh | bash
```

This script will:
- Verify that Java, Docker, and Docker Compose are properly installed
- Download and extract the AutoMQ installation package
- Create MinIO docker-compose configuration
- Create cluster project using `automq-cli.sh`
- Generate `topo.yaml` for a 3-node cluster

### Step 2: Start MinIO

Start MinIO using Docker Compose:

```bash
docker compose -f minio/docker-compose.yml up -d
```

Verify MinIO is running:

```bash
docker compose -f minio/docker-compose.yml ps
```

MinIO Console is available at: http://localhost:9001
- Username: `admin`
- Password: `automq_demo_secret`

### Step 3: Generate Startup Commands

Navigate to the AutoMQ directory and generate the startup commands:

```bash
cd automq-kafka-enterprise_5.3.4
bin/automq-cli.sh cluster deploy --dry-run clusters/local-demo
```

This command will:
- Verify the S3/MinIO configuration
- Output the startup commands for each node

### Step 4: Start AutoMQ Cluster

Execute the startup commands output from Step 3.

**For Local Pseudo-Cluster (all nodes on same machine):**

Since `automq-cli.sh` generates commands with default ports, you need to manually modify the ports for each node to avoid conflicts:

| Node | Broker Port | Controller Port |
|------|-------------|-----------------|
| 0    | 9092        | 19092           |
| 1    | 9093        | 19093           |
| 2    | 9094        | 19094           |

Modify these parameters in each startup command:

```bash
--override listeners=PLAINTEXT://127.0.0.1:<broker_port>,CONTROLLER://127.0.0.1:<controller_port>
--override advertised.listeners=PLAINTEXT://127.0.0.1:<broker_port>
--override controller.quorum.voters=0@127.0.0.1:19092,1@127.0.0.1:19093,2@127.0.0.1:19094
```

Run each modified command in a separate terminal.

**For Production (each node on separate machine):**

Simply execute the generated commands on each respective host without port modifications.

### Step 5: Verify Installation

Run the verification script:

```bash
./verify.sh
```

This script will:
- Check broker connectivity
- Create a test topic
- List all topics
- Test produce/consume
- Clean up the test topic

Or manually test with kafka commands:

Create a test topic:

```bash
bin/kafka-topics.sh --create --topic test-topic --bootstrap-server localhost:9092
```

List topics:

```bash
bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

Produce test messages:

```bash
bin/kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092
```

Consume test messages:

```bash
bin/kafka-console-consumer.sh --topic test-topic --from-beginning --bootstrap-server localhost:9092
```

## Cleanup

Run the cleanup script:

```bash
./cleanup.sh
```

This script will:
- Stop all AutoMQ nodes
- Stop MinIO and remove volumes
- Remove data directories (`/tmp/automq-data-*`)

To also remove downloaded packages and generated files:

```bash
./cleanup.sh --all
```

Or manually clean up:

Stop AutoMQ nodes:

```bash
cd automq-kafka-enterprise_5.3.4
bin/kafka-server-stop.sh
```

Stop MinIO:

```bash
cd ..
docker compose -f minio/docker-compose.yml down -v
```

Remove data:

```bash
rm -rf /tmp/automq-data-*
```

## Configuration Details

### Default Settings

| Component | Setting | Value |
|-----------|---------|-------|
| MinIO | Root User | admin |
| MinIO | Root Password | automq_demo_secret |
| MinIO | API Port | 9000 |
| MinIO | Console Port | 9001 |
| MinIO | Data Bucket | automq-data |
| MinIO | Ops Bucket | automq-ops |
| AutoMQ | Heap Size | 2GB per node |

### Cluster Topology (topo.yaml)

The `topo.yaml` file defines the cluster topology:

```yaml
global:
  config: |
    s3.data.buckets=0@s3://automq-data?region=us-east-1&endpoint=http://127.0.0.1:9000&pathStyle=true
    s3.ops.buckets=0@s3://automq-ops?region=us-east-1&endpoint=http://127.0.0.1:9000&pathStyle=true
    s3.wal.path=0@s3://automq-data?region=us-east-1&endpoint=http://127.0.0.1:9000&pathStyle=true
  envs:
    - name: KAFKA_S3_ACCESS_KEY
      value: 'admin'
    - name: KAFKA_S3_SECRET_KEY
      value: 'automq_demo_secret'
    - name: KAFKA_HEAP_OPTS
      value: '-Xmx2g -Xms2g'
controllers:
  - host: 127.0.0.1
    nodeId: 0
  - host: 127.0.0.1
    nodeId: 1
  - host: 127.0.0.1
    nodeId: 2
brokers: []
```

### Production Recommendations

For production deployments:

1. **Hardware**: Each node should have at least 2 CPU cores and 16GB RAM
2. **Storage**: Replace MinIO with a production object storage service (AWS S3, Azure Blob, etc.)
3. **Network**: Deploy nodes on separate machines with low-latency network
4. **Heap Size**: Increase JVM heap to 8GB or more based on workload
5. **Topology**: Update `topo.yaml` with actual host IPs

## Troubleshooting

### Java not found

Ensure Java 17+ is installed and `JAVA_HOME` is set:

```bash
java -version
export JAVA_HOME=/path/to/java
```

### MinIO connection refused

Check if MinIO is running:

```bash
docker compose -f minio/docker-compose.yml logs
```

### S3 connection error during deploy

Ensure MinIO is running and accessible:

```bash
curl http://localhost:9000/minio/health/live
```

### Port already in use

For local pseudo-cluster, ensure you've modified the ports correctly for each node.

### Cluster not forming

Ensure all nodes can communicate:
- All nodes must use the same `cluster.id`
- Controller quorum voters must be correctly configured
- Check firewall rules for the configured ports

## Reference

- [AutoMQ Documentation](https://docs.automq.com)
- [Deploy Multi-Nodes Cluster on Linux](https://www.automq.com/docs/automq/deployment/deploy-multi-nodes-cluster-on-linux)
- [Object Storage Configuration](https://www.automq.com/docs/automq/configuration/object-storage-configuration)
