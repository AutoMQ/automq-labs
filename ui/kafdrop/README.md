# AutoMQ Kafdrop Integration Demo

This demo shows how to integrate [Kafdrop](https://github.com/obsidiandynamics/kafdrop) with AutoMQ for a web-based Kafka cluster management interface.

## Overview

Kafdrop is a web UI for viewing Kafka topics and browsing consumer groups. It provides:

- 📊 **Broker Information**: View Kafka brokers, topic and partition assignments
- 📝 **Topic Management**: Browse topics, partition count, replication status
- 💬 **Message Browsing**: View messages with JSON, plain text, Avro and Protobuf support
- 👥 **Consumer Groups**: Monitor consumer group offsets and lag
- 🔧 **Topic Creation**: Create new topics through the web interface
- 🔐 **ACL Management**: View Access Control Lists

## Prerequisites

- Docker and Docker Compose installed
- Running AutoMQ cluster (not included in this demo)
- Network connectivity between Kafdrop and your AutoMQ brokers

## Quick Start

### 1. Configure AutoMQ Connection

Edit the `docker-compose.yml` file to point to your AutoMQ cluster:

```yaml
environment:
  KAFKA_BROKERCONNECT: "your-automq-broker1:9092,your-automq-broker2:9092"
```

### 2. Start Kafdrop

```bash
# Start Kafdrop
docker-compose up -d

# View logs
docker-compose logs -f kafdrop

# Stop Kafdrop
docker-compose down
```

### 3. Access Web Interface

Open your browser and navigate to:
```
http://localhost:12001
```

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BROKERCONNECT` | AutoMQ broker addresses | `localhost:9092` |
| `SERVER_SERVLET_CONTEXTPATH` | Web context path | `/` |
| `JVM_OPTS` | JVM memory settings | `-Xms32M -Xmx64M` |
| `SCHEMAREGISTRY_CONNECT` | Schema Registry URL | Not set |
| `SCHEMAREGISTRY_AUTH` | Schema Registry auth | Not set |
| `MESSAGE_FORMAT` | Default message format | `DEFAULT` |
| `MESSAGE_KEYFORMAT` | Default key format | `DEFAULT` |

### Message Format Support

Kafdrop supports multiple message formats:
- **DEFAULT**: Plain text messages
- **AVRO**: Avro serialized messages (requires Schema Registry)
- **PROTOBUF**: Protocol Buffer messages

### Schema Registry Integration

If your AutoMQ setup uses Schema Registry:

```yaml
environment:
  KAFKA_BROKERCONNECT: "your-automq-broker:9092"
  SCHEMAREGISTRY_CONNECT: "http://your-schema-registry:8081"
  SCHEMAREGISTRY_AUTH: "username:password"  # if auth required
  MESSAGE_FORMAT: "AVRO"
```

### Security Configuration

For SASL/TLS secured AutoMQ clusters, you can mount configuration files:

```yaml
volumes:
  - ./kafka-client.properties:/opt/kafdrop/kafka-client.properties:ro
environment:
  KAFKA_PROPERTIES_FILE: "/opt/kafdrop/kafka-client.properties"
```

## AutoMQ Integration Benefits

### Object Storage Optimization
- Kafdrop efficiently handles AutoMQ's object storage architecture
- Large topic browsing works seamlessly with AutoMQ's tiered storage
- Real-time monitoring of AutoMQ's elastic scaling capabilities

### Performance Monitoring
- Monitor AutoMQ's auto-balancing in real-time
- Track partition distribution across AutoMQ brokers
- Observe consumer lag with AutoMQ's optimized consumption

### Operational Insights
- Visualize AutoMQ's topic-level metrics
- Monitor AutoMQ's automatic partition rebalancing
- Track message throughput and storage efficiency

## Troubleshooting

### Common Issues

1. **Connection Refused**
   ```bash
   # Check AutoMQ broker connectivity
   telnet your-automq-broker 9092
   ```

2. **Topics Not Visible**
   - Verify broker addresses in `KAFKA_BROKERCONNECT`
   - Check AutoMQ cluster health
   - Ensure network connectivity

3. **Authentication Errors**
   - Configure SASL/TLS settings if AutoMQ uses security
   - Mount appropriate certificate files

4. **Memory Issues**
   ```yaml
   environment:
     JVM_OPTS: "-Xms64M -Xmx128M"  # Increase memory
   ```

### Logs and Debugging

```bash
# View Kafdrop logs
docker-compose logs kafdrop

# Follow logs in real-time
docker-compose logs -f kafdrop

# Check container status
docker-compose ps
```

## Advanced Configuration

### Custom Port

```yaml
ports:
  - "8080:9000"  # Access via http://localhost:8080
```

### Resource Limits

```yaml
deploy:
  resources:
    limits:
      memory: 256M
      cpus: '0.5'
```

### Health Checks

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:9000/actuator/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

## Production Considerations

1. **Security**: Use HTTPS and proper authentication
2. **Resource Limits**: Set appropriate memory and CPU limits
3. **Monitoring**: Integrate with your monitoring stack
4. **Backup**: Consider backing up Kafdrop configuration
5. **Updates**: Keep Kafdrop updated for security patches

## References

- [Kafdrop GitHub Repository](https://github.com/obsidiandynamics/kafdrop)
- [AutoMQ Documentation](https://www.automq.com/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## License

This demo configuration is provided under the same license terms as the AutoMQ project.