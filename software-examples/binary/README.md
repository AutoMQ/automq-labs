# AutoMQ Binary Deployment Quick Start

This guide explains how to deploy a 3-node AutoMQ cluster using the binary installation package with MinIO as the object storage backend.

> **Platform Support**: Scripts are tested on macOS and Linux. Windows users should use WSL2 or a Linux VM.

> **Note**: This is a quick start guide for local development and testing. For production deployments, refer to the official documentation.

## Prerequisites

- Linux or macOS operating system
- Docker and Docker Compose
- Java 17 or later
- At least 8GB available RAM

## Quick Start

### Step 1: Environment Setup

Run the setup script to download the installation package and generate configuration files:

```bash
./setup.sh
```

This script will:
- Check Java, Docker, and other dependencies
- Download and extract the AutoMQ installation package
- Create MinIO docker-compose configuration
- Generate configuration files for 3 nodes

### Step 2: Start MinIO

```bash
docker compose -f minio/docker-compose.yml up -d
```

Verify MinIO is running:

```bash
docker compose -f minio/docker-compose.yml ps
```

MinIO Console: http://localhost:9001
- Username: `admin`
- Password: `automq_demo_secret`

### Step 3: Format Storage

Format storage directories before first startup (only needed once):

```bash
cd automq-kafka-enterprise_5.3.4

# Format Node 0
bin/kafka-storage.sh format -t $(bin/kafka-storage.sh random-uuid) -c config/kraft/node0.properties

# Format Node 1 (use the same cluster-id from previous step)
bin/kafka-storage.sh format -t <cluster-id-from-previous-step> -c config/kraft/node1.properties

# Format Node 2 (use the same cluster-id)
bin/kafka-storage.sh format -t <cluster-id-from-previous-step> -c config/kraft/node2.properties
```

Or use the script to format all nodes at once:

```bash
cd ..
./format-storage.sh
```

### Step 4: Start AutoMQ Cluster

Run the following commands in 3 separate terminal windows:

**Terminal 1 - Start Node 0:**

```bash
cd automq-kafka-enterprise_5.3.4
export KAFKA_S3_ACCESS_KEY=admin
export KAFKA_S3_SECRET_KEY=automq_demo_secret
export KAFKA_HEAP_OPTS="-Xmx2g -Xms2g"
bin/kafka-server-start.sh config/kraft/node0.properties
```

**Terminal 2 - Start Node 1:**

```bash
cd automq-kafka-enterprise_5.3.4
export KAFKA_S3_ACCESS_KEY=admin
export KAFKA_S3_SECRET_KEY=automq_demo_secret
export KAFKA_HEAP_OPTS="-Xmx2g -Xms2g"
bin/kafka-server-start.sh config/kraft/node1.properties
```

**Terminal 3 - Start Node 2:**

```bash
cd automq-kafka-enterprise_5.3.4
export KAFKA_S3_ACCESS_KEY=admin
export KAFKA_S3_SECRET_KEY=automq_demo_secret
export KAFKA_HEAP_OPTS="-Xmx2g -Xms2g"
bin/kafka-server-start.sh config/kraft/node2.properties
```

### Step 5: Verify Installation

```bash
./verify.sh
```

Or test manually:

```bash
cd automq-kafka-enterprise_5.3.4

# Create a test topic
bin/kafka-topics.sh --create --topic test-topic --bootstrap-server localhost:9092

# List topics
bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Produce messages
bin/kafka-console-producer.sh --topic test-topic --bootstrap-server localhost:9092

# Consume messages
bin/kafka-console-consumer.sh --topic test-topic --from-beginning --bootstrap-server localhost:9092
```

## Stop Cluster

### Option 1: Use Kafka built-in command

```bash
cd automq-kafka-enterprise_5.3.4
bin/kafka-server-stop.sh
```

### Option 2: Press Ctrl+C in each terminal window

### Stop MinIO

```bash
docker compose -f minio/docker-compose.yml down
```

## Cleanup

Run the cleanup script:

```bash
./cleanup.sh
```

Full cleanup (including downloaded packages):

```bash
./cleanup.sh --all
```

## Configuration Details

### Cluster Port Configuration

| Node | Broker Port | Controller Port |
|------|-------------|-----------------|
| Node 0 | 9092 | 19092 |
| Node 1 | 9093 | 19093 |
| Node 2 | 9094 | 19094 |

### MinIO Configuration

| Setting | Value |
|---------|-------|
| Root User | admin |
| Root Password | automq_demo_secret |
| API Port | 9000 |
| Console Port | 9001 |
| Data Bucket | automq-data |
| Ops Bucket | automq-ops |

## Troubleshooting

### Java not found

Ensure Java 17+ is installed and `JAVA_HOME` is set:

```bash
java -version
export JAVA_HOME=/path/to/java
```

### MinIO connection failed

Check if MinIO is running:

```bash
docker compose -f minio/docker-compose.yml logs
curl http://localhost:9000/minio/health/live
```

### Port already in use

Check port usage:

```bash
lsof -i :9092
lsof -i :9093
lsof -i :9094
```

## Reference

- [AutoMQ Documentation](https://docs.automq.com)
- [Deploy Multi-Nodes Cluster on Linux](https://www.automq.com/docs/automq/deployment/deploy-multi-nodes-cluster-on-linux)
