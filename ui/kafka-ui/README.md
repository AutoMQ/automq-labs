# Kafka UI for AutoMQ

This directory contains Docker Compose configuration for launching Kafka UI to manage AutoMQ clusters. Kafka UI is a versatile, fast and lightweight web UI for managing Apache Kafka® clusters.

## Features

Kafka UI provides comprehensive features for AutoMQ cluster management:

- **Multi-Cluster Management**: Monitor and manage all your clusters in one place
- **Performance Monitoring**: Track key Kafka metrics with a lightweight dashboard
- **Broker Management**: View topic and partition assignments, controller status
- **Topic Management**: View partition count, replication status, and custom configuration
- **Consumer Groups**: View per-partition parked offsets, combined and per-partition lag
- **Message Browser**: Browse messages with JSON, plain text, and Avro encoding
- **Dynamic Topic Configuration**: Create and configure new topics with dynamic configuration
- **Schema Registry Support**: Manage Avro, JSON Schema, and Protobuf schemas
- **Kafka Connect Integration**: Manage connectors and view their status
- **Security Features**: Configurable authentication and role-based access control
- **Data Masking**: Obfuscate sensitive data in topic messages

## Quick Start

### Prerequisites

1. Ensure your AutoMQ cluster is running and connected to the `automq_net` network
2. Ensure Docker and Docker Compose are installed

### Access Kafka UI

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
- `automq-broker-1:9092`
- `automq-broker-2:9092`
- `automq-broker-3:9092`

The default configuration assumes your AutoMQ cluster has the following broker:
- `server1:9092`

If your broker names or ports are different, or if you have a multi-broker setup, please modify the `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS` environment variable in `docker-compose.yml` to include all your brokers (e.g., `broker1:9092,broker2:9092,broker3:9092`).

### Security Configuration

If your AutoMQ cluster has security authentication enabled, please uncomment and configure the following environment variables in `docker-compose.yml`:

```yaml
# Security Protocol
KAFKA_CLUSTERS_0_PROPERTIES_SECURITY_PROTOCOL: "SASL_SSL"

# SASL Configuration
KAFKA_CLUSTERS_0_PROPERTIES_SASL_MECHANISM: "PLAIN"  # or "SCRAM-SHA-256", "SCRAM-SHA-512"
KAFKA_CLUSTERS_0_PROPERTIES_SASL_JAAS_CONFIG: "org.apache.kafka.common.security.plain.PlainLoginModule required username='your-username' password='your-password';"

# SSL Configuration
KAFKA_CLUSTERS_0_PROPERTIES_SSL_TRUSTSTORE_LOCATION: "/etc/kafka/secrets/kafka.client.truststore.jks"
KAFKA_CLUSTERS_0_PROPERTIES_SSL_TRUSTSTORE_PASSWORD: "your-truststore-password"
```

### Optional Service Configuration

If you have the following services in your environment, you can uncomment the corresponding configurations:

#### Schema Registry
```yaml
KAFKA_CLUSTERS_0_SCHEMAREGISTRY: "http://schema-registry:8081"
```

#### Kafka Connect
```yaml
KAFKA_CLUSTERS_0_KAFKACONNECT_0_NAME: "AutoMQ Connect"
KAFKA_CLUSTERS_0_KAFKACONNECT_0_ADDRESS: "http://kafka-connect:8083"
```

#### KSQL DB
```yaml
KAFKA_CLUSTERS_0_KSQLDBSERVER: "http://ksqldb:8088"
```

### Advanced Configuration

For advanced configuration options, you can create a custom configuration file:

1. Create a `config` directory:
```bash
mkdir -p config
```

2. Create `config/application.yml` with your custom settings

3. Uncomment the volumes section in `docker-compose.yml`:
```yaml
volumes:
  - ./config/application.yml:/etc/kafkaui/dynamic_config.yaml
```

## Network Configuration

This configuration uses the external network `automq_net`. Ensure:
1. The network exists
2. Your AutoMQ cluster is connected to the same network
3. Broker service names can be resolved within the network

To create the network if it doesn't exist:
```bash
docker network create automq_net
```

## Troubleshooting

### Connection Issues

If Kafka UI cannot connect to the AutoMQ cluster:

1. **Check broker addresses**: Verify the broker addresses in `KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS`
2. **Network connectivity**: Ensure both services are on the same Docker network
3. **Firewall settings**: Check if ports are accessible
4. **Authentication**: Validate security configuration if enabled
5. **DNS resolution**: Ensure broker hostnames can be resolved

### View Logs

```bash
# View Kafka UI logs
docker-compose logs kafka-ui

# Follow logs in real-time
docker-compose logs -f kafka-ui

# View last 100 lines
docker-compose logs --tail=100 kafka-ui
```

### Health Check

Kafka UI includes a health check endpoint:
- **URL**: http://localhost:8080/actuator/health
- **Status**: Returning "UP" status indicates the service is healthy

### Common Issues

1. **Port conflicts**: If port 8080 is already in use, change the port mapping in `docker-compose.yml`
2. **Memory issues**: Increase Docker memory limits if the container fails to start
3. **Permission issues**: Ensure Docker has proper permissions to access volumes

## Performance Tuning

For better performance with large clusters:

1. **Increase JVM memory**:
```yaml
environment:
  JAVA_OPTS: "-Xmx2g -Xms1g"
```

2. **Adjust logging levels**:
```yaml
LOGGING_LEVEL_ROOT: "WARN"
LOGGING_LEVEL_COM_PROVECTUS: "INFO"
```

3. **Configure connection pooling**:
```yaml
KAFKA_CLUSTERS_0_PROPERTIES_CONNECTIONS_MAX_IDLE_MS: "300000"
KAFKA_CLUSTERS_0_PROPERTIES_REQUEST_TIMEOUT_MS: "30000"
```

## Security Best Practices

1. **Use environment files**: Store sensitive configuration in `.env` files
2. **Enable authentication**: Configure OAuth 2.0 or LDAP authentication
3. **Set up RBAC**: Configure role-based access control
4. **Use HTTPS**: Configure SSL/TLS for web interface
5. **Network isolation**: Use proper Docker network segmentation

## More Information

- [Kafka UI Official Repository](https://github.com/provectus/kafka-ui)
- [Kafka UI Documentation](https://docs.kafka-ui.provectus.io/)
- [AutoMQ Documentation](https://docs.automq.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)