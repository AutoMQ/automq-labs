# AutoMQ Client Examples

This directory contains comprehensive client examples for interacting with AutoMQ using different programming languages. Each example demonstrates both basic and advanced Kafka operations with performance metrics and best practices optimized for AutoMQ's object storage architecture.

## Common Design Principles

All client examples in this repository share the following characteristics:

🎯 **Community-Recommended Clients**: Each example uses the client library recommended by both AutoMQ and the Apache Kafka community for optimal compatibility and performance.

⚙️ **AutoMQ Best Practices**: All clients are pre-configured with parameters following AutoMQ's recommended [best practices](https://www.automq.com/docs/automq-cloud/getting-started/client-sdk-guide), including optimized batch sizes, linger times, and timeout settings for object storage architecture.

🐳 **Docker Compose Ready**: Every example includes Docker Compose configuration for quick deployment and can be seamlessly integrated with AutoMQ cluster Docker Compose setups.

📊 **Built-in Metrics**: All examples automatically print comprehensive performance metrics including latency measurements, throughput statistics, and operational insights.

🚀 **Production-Ready**: Examples demonstrate real-world patterns with proper error handling, resource management, and concurrent processing capabilities.

## Available Client Examples

### 🔥 [Java Examples](./java/)

Java examples using the Apache Kafka client library with Maven build system.

**Available Examples:**
- **SimpleMessageExample**: Basic producer/consumer operations
- **TransactionalMessageExample**: ACID-compliant transactional messaging
- **HubSpotContactDemo**: Real-world integration example
- Performance metrics and Docker support included

### 🚀 [Go Examples](./go/)

Go examples using the franz-go client library.

**Available Examples:**
- **SimpleMessageExample**: Basic producer/consumer operations
- **TransactionalMessageExample**: Transactional operations with ACID guarantees
- Performance metrics and Docker support included

### 🐍 [Python Examples](./python/)

Python examples using the kafka-python library.

**Available Examples:**
- **SimpleMessageExample**: Basic producer/consumer operations
- Performance metrics and Docker support included
- Multiple execution methods (direct Python, Docker, shell script)

### ⚡ [C++ Examples](./cpp/)

*Note: C++ examples are currently TODO. Implementation is planned for future releases.*

### 🌐 JavaScript Examples

*Note: JavaScript examples are currently TODO. Implementation is planned for future releases.*

### 🦀 Rust Examples

*Note: Rust examples are currently TODO. Implementation is planned for future releases.*

## Common Features Across All Examples

### 🎯 **Performance Metrics**
All examples provide detailed performance analytics:
- **Total Messages**: Configured message count
- **Messages Sent/Received**: Actual successful operations
- **Total Execution Time**: End-to-end processing time
- **Average Produce Latency**: Time from send() to broker acknowledgment
- **Average End-to-End Latency**: Time from message creation to consumption
- **Consume Time**: Duration of the consumption phase

### 🔧 **AutoMQ Optimizations**
All clients are configured with AutoMQ-specific optimizations:
- **Batch Size**: 1MB for optimal object storage performance
- **Linger Time**: 100ms for efficient message batching
- **Max Request Size**: 16MB for large message batches
- **Metadata Refresh**: 60 seconds for balanced performance
- **Acknowledgments**: "all" for durability guarantees

### 🐳 **Docker Support**
Every example includes:
- Dockerfile with multi-stage builds
- Docker Compose configuration
- Environment variable configuration
- Network integration with AutoMQ clusters
- Security best practices (non-root execution)

### 🔒 **Production-Ready Features**
- Comprehensive error handling and retry logic
- Proper resource management and cleanup
- Configurable timeouts and connection settings
- Logging with appropriate levels
- Thread-safe operations and concurrency handling

## Quick Start

### Prerequisites
- Running AutoMQ cluster
- Docker and Docker Compose (for containerized deployment)
- Language-specific requirements (see individual README files)

### Running Examples

Each language directory contains detailed instructions, but here's a quick overview:

```bash
# Java
cd java && mvn clean package && docker compose up --build

# Go
cd go && go build -o kafka-examples . && ./kafka-examples

# Python
cd python && ./run.sh

# Or use Docker for any language
cd <language> && docker compose up --build
```

### Configuration

All examples support environment variable configuration:
- `BOOTSTRAP_SERVERS`: AutoMQ broker addresses (default: localhost:9092)
- Additional language-specific variables (see individual READMEs)

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Producer      │    │   AutoMQ        │    │   Consumer      │
│                 │───▶│   Cluster       │───▶│                 │
│ • Batching      │    │                 │    │ • Group Mgmt    │
│ • Compression   │    │ • Object Store  │    │ • Offset Mgmt   │
│ • Retries       │    │ • Partitioning  │    │ • Rebalancing   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Performance Tuning

For optimal performance with AutoMQ:

1. **Batch Configuration**: Use larger batch sizes (1MB) to reduce object storage operations
2. **Linger Time**: Set appropriate linger time (100ms) for batching efficiency
3. **Compression**: Enable compression for better network utilization
4. **Connection Pooling**: Reuse connections and clients when possible
5. **Monitoring**: Use the built-in metrics for performance analysis

## Troubleshooting

### Common Issues

1. **Connection Refused**: Verify AutoMQ cluster is running and accessible
2. **Topic Not Found**: Ensure topics exist or enable auto-creation
3. **Permission Denied**: Check Kafka ACLs and authentication settings
4. **High Latency**: Review batch size and linger time configuration
5. **Memory Issues**: Adjust JVM settings or container memory limits

### Getting Help

- Check individual language README files for specific guidance
- Review AutoMQ documentation: https://www.automq.com/docs
- Examine log files in the `logs/` directory of each example
- Use Docker logs: `docker compose logs -f`

## Contributing

We welcome contributions to improve these examples:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Update documentation
5. Submit a pull request

## License

These examples are provided under the same license as the AutoMQ project.