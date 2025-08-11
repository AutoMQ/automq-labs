# Redpanda Console for AutoMQ

This directory contains Docker Compose configuration for launching Redpanda Console to manage AutoMQ clusters.

## Features

Redpanda Console provides the following features to manage your AutoMQ cluster:

- **Message Viewer**: Browse and search topic messages through dynamic filters and JavaScript functions
- **Consumer Group Management**: View, edit, and delete consumer groups and their offsets
- **Topic Overview**: Browse topic lists, configurations, space usage, and partition details
- **Cluster Overview**: View broker information, health status, and configurations
- **Security Management**: Manage Kafka ACLs and SASL-SCRAM users
- **Schema Registry**: Manage Avro, Protobuf, or JSON schemas (if available)
- **Kafka Connect**: Manage connectors (if available)

## Quick Start

### Prerequisites

1. Ensure your AutoMQ cluster is running and connected to the `automq_net` network
2. Ensure Docker and Docker Compose are installed

### Start Redpanda Console

```bash
# Navigate to directory
cd /Users/luo/Desktop/AutoMQ/code/automq-labs/ui/redpanda-console/

# Start services
docker-compose up -d

# View logs
docker-compose logs -f redpanda-console
```

### Access Console

After successful startup, access in your browser:
- **URL**: http://localhost:8080
- **Port**: 8080

### Stop Services

```bash
docker-compose down
```

## Configuration

### Broker Configuration

The default configuration assumes your AutoMQ cluster has the following brokers:
- `server1:9092`

If your broker names or ports are different, please modify the `KAFKA_BROKERS` environment variable in `docker-compose.yml`.

### Security Configuration

If your AutoMQ cluster has security authentication enabled, please uncomment and configure the following environment variables:

```yaml
# TLS Configuration
KAFKA_TLS_ENABLED: "true"

# SASL Configuration
KAFKA_SASL_ENABLED: "true"
KAFKA_SASL_MECHANISM: "PLAIN"  # or "SCRAM-SHA-256", "SCRAM-SHA-512"
KAFKA_SASL_USERNAME: "your-username"
KAFKA_SASL_PASSWORD: "your-password"
```

### Optional Service Configuration

If you have the following services in your environment, you can uncomment the corresponding configurations:

#### Schema Registry
```yaml
KAFKA_SCHEMAREGISTRY_ENABLED: "true"
KAFKA_SCHEMAREGISTRY_URLS: "http://schema-registry:8081"
```

#### Kafka Connect
```yaml
CONNECT_ENABLED: "true"
CONNECT_CLUSTERS_NAME: "local-connect"
CONNECT_CLUSTERS_URL: "http://kafka-connect:8083"
```

## Network Configuration

This configuration uses the external network `automq_net`. Ensure:
1. The network exists
2. Your AutoMQ cluster is connected to the same network
3. Broker service names can be resolved within the network

## Troubleshooting

### Connection Issues

If Console cannot connect to the AutoMQ cluster:

1. Check if broker addresses are correct
2. Verify network connectivity
3. Check firewall settings
4. Validate authentication configuration (if enabled)

### View Logs

```bash
# View Console logs
docker-compose logs redpanda-console

# Follow logs in real-time
docker-compose logs -f redpanda-console
```

### Health Check

Console includes a health check endpoint:
- **URL**: http://localhost:8080/api/cluster
- **Status**: Returning cluster information indicates normal connection

## More Information

- [Redpanda Console Official Documentation](https://github.com/redpanda-data/console)
- [AutoMQ Documentation](https://docs.automq.com/)