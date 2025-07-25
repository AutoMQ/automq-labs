# Java Kafka Client Examples

This directory contains sample code for interacting with Kafka using Java, including regular messages and transactional messages production and consumption.

## Prerequisites

- Java 8+
- Maven 3.6+
- Accessible AutoMQ cluster

## Building the Project

```bash
mvn clean package
```

## Configuration

The `AutoMQExampleConstants` class contains all the configuration parameters used in the examples:

AutoMQ does not rely on local disks and directly writes data to object storage. Compared to writing to local disks, the file creation operation in object storage has higher latency. Therefore, the following parameters can be configured on the client-side. For details, you can refer to the AutoMQ documentation at https://www.automq.com/docs/automq/configuration/performance-tuning-for-client

## Available Examples

### 1. SimpleMessageExample

Demonstrates basic Kafka producer and consumer functionality with performance metrics.

**Features:**
- Concurrent message production and consumption
- Real-time performance monitoring
- End-to-end latency measurement
- Producer acknowledgment latency tracking

### 2. TransactionalMessageExample

Demonstrates transactional Kafka operations with ACID guarantees.

**Features:**
- Transactional message production
- Read-committed consumer isolation
- Atomic message processing
- Transaction rollback on errors
- Performance metrics for transactional operations

## Docker Support

The project includes Docker support for easy deployment and testing:

**Build and run with Docker Compose:**
```bash
# Build and start the container
docker compose up --build

# View logs
docker compose logs -f

# Stop the container
docker compose down
```

**Environment Variables:**
- `BOOTSTRAP_SERVERS`: Kafka broker addresses (default: localhost:9092)
- `JAVA_OPTS`: JVM options (default: -Xmx512m -Xms256m)

## Performance Metrics Explanation

- **Total Messages**: Number of messages configured to send/receive
- **Messages Sent**: Actual number of messages successfully sent
- **Messages Received**: Actual number of messages successfully consumed
- **Total Time**: Complete execution time from start to finish
- **Consume Time**: Time spent in the consumer loop
- **Average Produce Latency**: Average time from send() call to broker acknowledgment
- **Average End-to-End Latency**: Average time from message production to consumption

