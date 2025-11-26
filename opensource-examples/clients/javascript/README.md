# AutoMQ JavaScript/Node.js Client Examples

This directory contains JavaScript/Node.js client examples for AutoMQ, demonstrating how to use the KafkaJS library to interact with AutoMQ clusters efficiently.

## Prerequisites

- **Node.js**: Version 16 or higher
- **npm**: Version 7 or higher
- **AutoMQ Cluster**: A running AutoMQ cluster

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configuration

The examples use optimized configurations for AutoMQ's object storage architecture. Key settings are defined in `src/config/automqConfig.js`:

- **Bootstrap Servers**: Configure via `BOOTSTRAP_SERVERS` environment variable (default: `localhost:9092`)
- **Performance Tuning**: Optimized batch size, linger time, and fetch settings for AutoMQ
- **Topics**: Pre-configured topic names for simple and transactional examples

For detailed performance tuning guidelines, refer to the [AutoMQ Performance Tuning Documentation](https://docs.automq.com/docs/automq-s3kafka/YUzOwI8CgiNIHDkUw8Oc3HXXnWh).

### 3. Run Examples

#### Interactive Mode (Recommended)

```bash
./run-examples.sh
```

#### Direct Commands

```bash
# Simple Message Example
npm run simple
# or
node src/examples/simpleMessageExample.js

# Transactional Message Example
npm run transactional
# or
node src/examples/transactionalMessageExample.js
```

#### Custom Message Count

```bash
# Send 100 messages
MESSAGE_COUNT=100 npm run simple
```

## Available Examples

### 1. Simple Message Example (`simpleMessageExample.js`)

**Features:**
- Basic producer and consumer implementation
- Performance metrics collection
- AutoMQ-optimized configurations
- Batch processing for improved throughput
- Latency measurement (produce and end-to-end)

**Use Cases:**
- Basic message publishing and consumption
- Performance testing and benchmarking
- Learning AutoMQ client basics

### 2. Transactional Message Example (`transactionalMessageExample.js`)

**Features:**
- Transactional producer with exactly-once semantics
- Consumer with read-committed isolation level
- Transaction rollback on errors
- Performance metrics for transactional operations
- Unique transaction ID generation

**Use Cases:**
- Financial transactions requiring exactly-once processing
- Critical data pipelines with strong consistency requirements
- Multi-step operations that need atomicity

## Docker Support

### Build and Run with Docker

```bash
# Build the Docker image
docker build -t automq-javascript-examples .

# Run with default settings
docker run --rm automq-javascript-examples

# Run with custom bootstrap servers
docker run --rm -e BOOTSTRAP_SERVERS=your-broker:9092 automq-javascript-examples

# Run specific example
docker run --rm automq-javascript-examples ./run-examples.sh simple
```

### Docker Compose

```bash
# Run with docker-compose
docker-compose up

# Run with custom environment
BOOTSTRAP_SERVERS=your-broker:9092 docker-compose up
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|----------|
| `BOOTSTRAP_SERVERS` | Kafka bootstrap servers | `localhost:9092` |
| `MESSAGE_COUNT` | Number of messages to send | `20` |
| `NODE_ENV` | Node.js environment | `development` |

## Performance Metrics

Both examples collect and display comprehensive performance metrics:

- **Total Messages**: Number of messages sent and received
- **Total Time**: Complete execution time
- **Consume Time**: Time taken to consume all messages
- **Average Produce Latency**: Time from send request to acknowledgment
- **Average End-to-End Latency**: Time from message creation to consumption
- **Throughput**: Messages per second

### Sample Output

```
=== Performance Metrics ===
Total Messages: 20
Messages Sent: 20
Messages Received: 20
Total Time: 1250 ms
Consume Time: 890 ms
Average Produce Latency: 15.30 ms
Average End-to-End Latency: 45.20 ms
===============================
```

## Configuration Details

### AutoMQ Optimizations

The examples include several optimizations specific to AutoMQ's architecture:

- **Metadata Refresh**: Reduced `metadataMaxAge` for faster topic discovery
- **Batch Processing**: Optimized `batchSize` and `lingerMs` for object storage
- **Request Sizing**: Increased `maxRequestSize` for larger batches
- **Fetch Optimization**: Tuned `maxPartitionFetchBytes` for efficient reads
- **Connection Management**: Optimized timeouts for cloud environments

### Producer Configuration

```javascript
{
  acks: 'all',                    // Wait for all replicas
  retries: 3,                     // Retry failed sends
  batchSize: 65536,              // 64KB batches
  lingerMs: 10,                  // Wait 10ms for batching
  maxRequestSize: 10485760,      // 10MB max request
  metadataMaxAge: 30000          // 30s metadata refresh
}
```

### Consumer Configuration

```javascript
{
  sessionTimeout: 30000,          // 30s session timeout
  heartbeatInterval: 3000,        // 3s heartbeat
  maxPartitionFetchBytes: 2097152, // 2MB fetch size
  isolationLevel: 'read_committed' // For transactional consumers
}
```

## Troubleshooting

### Common Issues

1. **Connection Errors**
   - Verify `BOOTSTRAP_SERVERS` is correct
   - Check network connectivity to AutoMQ cluster
   - Ensure security configurations match cluster settings

2. **Performance Issues**
   - Review batch size and linger time settings
   - Check network latency to AutoMQ cluster
   - Monitor AutoMQ cluster performance

3. **Transaction Failures**
   - Verify transactional producer configuration
   - Check transaction timeout settings
   - Ensure unique transactional IDs

### Debug Mode

Enable debug logging by setting the log level:

```bash
LOG_LEVEL=debug npm run simple
```

## Development

### Project Structure

```
javascript/
├── src/
│   ├── config/
│   │   └── automqConfig.js      # AutoMQ configuration constants
│   └── examples/
│       ├── simpleMessageExample.js
│       └── transactionalMessageExample.js
├── run-examples.sh              # Shell script runner
├── package.json                 # Dependencies and scripts
├── Dockerfile                   # Container image definition
├── docker-compose.yml           # Docker Compose configuration
└── README.md                    # This file
```

### Adding New Examples

1. Create a new file in `src/examples/`
2. Implement the example class with `run()` method
3. Add npm script to `package.json`
4. Update `run-examples.sh` if needed
5. Document the new example in this README

## Dependencies

- **kafkajs**: Apache Kafka client for Node.js
- **winston**: Logging library
- **dotenv**: Environment variable loader
- **uuid**: UUID generation for unique identifiers

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests for any improvements.

## Support

For questions and support:
- [AutoMQ Documentation](https://docs.automq.com/)
- [AutoMQ Community](https://github.com/AutoMQ/automq)
- [Issue Tracker](https://github.com/AutoMQ/automq-labs/issues)