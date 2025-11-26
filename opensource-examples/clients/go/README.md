# Go Kafka Client Examples

This directory contains sample code for interacting with Kafka using Go and the [franz-go](https://github.com/twmb/franz-go) client library, including regular messages and transactional messages production and consumption.

## Prerequisites

- Go 1.21+
- Docker and Docker Compose (for containerized deployment)
- Accessible AutoMQ cluster

## Building the Project

### Local Build

```bash
# Download dependencies
go mod download

# Build the application
go build -o kafka-examples .

# Run examples
./kafka-examples -example=all
```

### Available Example Types

- `simple`: Run only the simple message example
- `transactional`: Run only the transactional message example  
- `all`: Run both examples (default)

```bash
# Run specific example
./kafka-examples -example=simple
./kafka-examples -example=transactional
```

## Configuration

The `config.AutoMQExampleConstants` struct contains all the configuration parameters used in the examples:

AutoMQ does not rely on local disks and directly writes data to object storage. Compared to writing to local disks, the file creation operation in object storage has higher latency. Therefore, the following parameters can be configured on the client-side. For details, you can refer to the AutoMQ documentation at https://www.automq.com/docs/automq/configuration/performance-tuning-for-client

### Key Configuration Parameters

- **Bootstrap Servers**: Configurable via `BOOTSTRAP_SERVERS` environment variable (default: `localhost:9092`)
- **Batch Size**: 1MB for optimal throughput with AutoMQ's object storage
- **Linger Time**: 100ms to batch messages efficiently
- **Metadata Refresh**: 60 seconds to balance freshness and performance
- **Acknowledgments**: "all" for durability guarantees
- **Max Request Size**: 16MB to handle large message batches

## Available Examples

### 1. SimpleMessageExample

Demonstrates basic Kafka producer and consumer functionality with performance metrics.

**Features:**
- Concurrent message production and consumption using goroutines
- Real-time performance monitoring
- End-to-end latency measurement
- Producer acknowledgment latency tracking
- JSON message payload with timestamps

**Key Components:**
- Producer: Sends 20 messages with performance tracking
- Consumer: Consumes messages with latency calculation
- Metrics: Detailed performance statistics

### 2. TransactionalMessageExample

Demonstrates transactional Kafka operations with ACID guarantees using franz-go's transaction support.

**Features:**
- Transactional message production with commit/abort semantics
- Read-committed consumer isolation level
- Atomic message processing
- Transaction rollback on errors
- Performance metrics for transactional operations

**Key Components:**
- Transactional Producer: Uses `TransactionalID` for exactly-once semantics
- Read-Committed Consumer: Only reads committed messages
- Error Handling: Automatic transaction abort on failures

## Docker Support

The project includes Docker support for easy deployment and testing:

### Build and run with Docker Compose:

```bash
# Build and start the container
docker compose up --build

# View logs
docker compose logs -f

# Stop the container
docker compose down
```

### Environment Variables:

- `BOOTSTRAP_SERVERS`: Kafka broker addresses (default: `localhost:9092`)

### Docker Build Process:

1. **Build Stage**: Uses `golang:1.21-alpine` to compile the Go application
2. **Runtime Stage**: Uses minimal `alpine:latest` for security and size
3. **Security**: Runs as non-root user (`appuser:appgroup`)
4. **Dependencies**: Includes CA certificates for secure connections

## Franz-Go Client Features Used

### Producer Features:
- **Batch Configuration**: Optimized batch sizes for AutoMQ
- **Linger Settings**: Efficient message batching
- **Acknowledgment Control**: Configurable durability guarantees
- **Transactional Support**: ACID compliance with `BeginTransaction()`, `Commit()`, and `Abort()`

### Consumer Features:
- **Consumer Groups**: Automatic partition assignment and rebalancing
- **Offset Management**: Configurable offset reset strategies
- **Isolation Levels**: Support for read-committed transactions
- **Fetch Optimization**: Tuned fetch sizes for AutoMQ's characteristics

## Performance Metrics Explanation

Both examples provide detailed performance metrics:

- **Total Messages**: Number of messages configured to send/receive
- **Messages Sent**: Actual number of messages successfully sent
- **Messages Received**: Actual number of messages successfully consumed
- **Total Time**: Complete execution time from start to finish
- **Consume Time**: Time spent in the consumer loop
- **Average Produce Latency**: Average time from send() call to broker acknowledgment
- **Average End-to-End Latency**: Average time from message production to consumption

### Sample Output:

```
=== Simple Message Example Performance Metrics ===
Total Messages: 20
Messages Sent: 20
Messages Received: 20
Total Time: 2.345s
Consume Time: 1.234s
Average Produce Latency: 45.67 ms
Average End-to-End Latency: 123.45 ms
=================================================
```

## Code Structure

```
go/
├── config/
│   └── constants.go          # Configuration constants
├── examples/
│   ├── simple_message_example.go      # Basic producer/consumer
│   └── transactional_message_example.go  # Transactional operations
├── bin/
│   └── run-examples.sh       # Execution script
├── main.go                   # Application entry point
├── go.mod                    # Go module definition
├── go.sum                    # Dependency checksums
├── Dockerfile                # Container build instructions
├── docker-compose.yml        # Container orchestration
└── README.md                 # This documentation
```

## Error Handling

The examples include comprehensive error handling:

- **Connection Errors**: Automatic retries with configurable limits
- **Transaction Errors**: Automatic rollback on failures
- **Serialization Errors**: JSON marshaling/unmarshaling error handling
- **Consumer Errors**: Graceful handling of fetch errors
- **Timeout Handling**: Configurable timeouts for all operations

## Best Practices Demonstrated

1. **Resource Management**: Proper client lifecycle with `defer client.Close()`
2. **Concurrency**: Safe concurrent access using atomic operations and mutexes
3. **Configuration**: Environment-based configuration for flexibility
4. **Monitoring**: Comprehensive metrics collection and reporting
5. **Security**: Non-root container execution and proper error handling
6. **Performance**: Optimized settings for AutoMQ's object storage architecture

## Troubleshooting

### Common Issues:

1. **Connection Failed**: Verify `BOOTSTRAP_SERVERS` environment variable
2. **Topic Not Found**: Ensure topics exist or enable auto-creation
3. **Permission Denied**: Check Kafka ACLs and authentication settings
4. **Transaction Timeout**: Increase transaction timeout for slow networks

### Debug Mode:

```bash
# Enable verbose logging
export KAFKA_LOG_LEVEL=debug
./kafka-examples -example=all
```

## Contributing

When contributing to this example:

1. Follow Go best practices and formatting (`go fmt`)
2. Add comprehensive comments for complex operations
3. Include error handling for all operations
4. Update documentation for new features
5. Test with both single-node and cluster deployments

## References

- [Franz-Go Documentation](https://github.com/twmb/franz-go)
- [AutoMQ Documentation](https://www.automq.com/docs)
- [Kafka Protocol Documentation](https://kafka.apache.org/protocol)
- [Go Best Practices](https://golang.org/doc/effective_go.html)