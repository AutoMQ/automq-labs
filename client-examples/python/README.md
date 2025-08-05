# Python Kafka Client Examples

This directory contains sample code for interacting with Kafka using Python for message production and consumption.

## Prerequisites

- Python 3.8+
- pip (Python package manager)
- Accessible AutoMQ cluster

## Dependencies

The project uses the following main dependencies:
- `kafka-python==2.2.15` - Pure Python Kafka client library (upgraded for better compatibility)
- `loguru==0.7.2` - Modern logging library for Python

## Configuration

The `AutoMQExampleConstants` class contains all the configuration parameters used in the examples:

### Key Configuration Parameters

**Producer Batching Configuration:**
- `BATCH_SIZE = 1048576` (1MB) - Maximum bytes per batch
- `LINGER_MS = 100` (100ms) - Maximum wait time for batching
- `MAX_REQUEST_SIZE = 16777216` (16MB) - Maximum request size
- `ACKS = 'all'` - Wait for all replicas acknowledgment

**Consumer Configuration:**
- `SESSION_TIMEOUT_MS = 30000` (30s) - Session timeout
- `REQUEST_TIMEOUT_MS = 40000` (40s) - Request timeout (must be > session timeout)
- `MAX_PARTITION_FETCH_BYTES = 8388608` (8MB) - Maximum fetch size per partition

AutoMQ does not rely on local disks and directly writes data to object storage. Compared to writing to local disks, the file creation operation in object storage has higher latency. Therefore, the following parameters can be configured on the client-side. For details, you can refer to the AutoMQ documentation at https://www.automq.com/docs/automq/configuration/performance-tuning-for-client

## Available Examples

### 1. SimpleMessageExample

Demonstrates basic Kafka producer and consumer functionality with performance metrics.

**Features:**
- Concurrent message production and consumption
- Real-time performance monitoring
- End-to-end latency measurement
- Producer acknowledgment latency tracking



## Running Examples

### Method 1: Using run.sh Script (Recommended)

```bash
# Install dependencies
./run.sh install

# Run examples (default behavior)
./run.sh

# Show help
./run.sh help
```

### Method 2: Direct Python Execution

```bash
# Install dependencies
pip install -r requirements.txt

# Run all examples
python run_examples.py

# Or run individual example
python simple_message_example.py
```

### Method 3: Docker Compose

```bash
# Build and start the container
docker compose up --build

# View logs
docker compose logs -f

# Stop the container
docker compose down
```

### Method 4: Docker Build and Run

```bash
# Build the Docker image
docker build -t automq-python-examples .

# Run the container
docker run --rm \
  -e BOOTSTRAP_SERVERS=localhost:9092 \
  automq-python-examples
```

## Performance Metrics

Both examples output comprehensive performance metrics:

```
=== Performance Metrics ===
Total Messages: 20
Messages Sent: 20
Messages Received: 20
Total Time: 1234.56 ms
Consume Time: 987.65 ms
Average Produce Latency: 12.34 ms
Average End-to-End Latency: 45.67 ms
===========================
```

**Metrics Explanation:**
- **Total Messages**: Number of messages configured to send
- **Messages Sent**: Actual number of messages successfully sent
- **Messages Received**: Actual number of messages successfully received
- **Total Time**: Total execution time from start to finish
- **Consume Time**: Time from receiving first message to last message
- **Average Produce Latency**: Average time from send to acknowledgment
- **Average End-to-End Latency**: Average time from message creation to consumption

## Docker Support

The project includes Docker support for easy deployment and testing:

**Environment Variables:**
- `BOOTSTRAP_SERVERS`: Kafka broker addresses (default: server1:9092)

**Network Configuration:**
The Docker Compose configuration uses the `automq_net` external network, which should be created by the AutoMQ deployment. This allows the Python examples to communicate with AutoMQ services running in the same Docker network.

**Usage with AutoMQ:**
1. First, start your AutoMQ cluster using the main docker-compose setup
2. Then run the Python examples which will connect to the same network

```bash
# Start AutoMQ (from the main project directory)
cd ../../opensource-setup/docker-compose
docker compose up -d

# Run Python examples (from this directory)
cd ../../client-examples/python
docker compose up --build
```

## Troubleshooting

### Common Issues

1. **Connection refused**: Ensure AutoMQ cluster is running and accessible
2. **Network issues**: Verify that the `automq_net` network exists when using Docker
3. **Permission errors**: Make sure the Docker user has proper permissions

### Checking Network

```bash
# Check if the automq_net network exists
docker network ls | grep automq_net

# If not exists, create it (usually done by AutoMQ setup)
docker network create automq_net
```

## Code Structure

- `automq_example_constants.py` - Configuration constants optimized for AutoMQ
- `simple_message_example.py` - Basic producer/consumer example with kafka-python 2.2.15 compatibility
- `run_examples.py` - Script to run all examples sequentially
- `run.sh` - Simplified shell script for easy execution
- `requirements.txt` - Python dependencies
- `Dockerfile` - Docker image configuration
- `docker-compose.yml` - Docker Compose service definition

## Recent Updates

### kafka-python 2.2.15 Compatibility

The examples have been updated for kafka-python 2.2.15 with the following improvements:

1. **Removed deprecated parameters** - `consumer_timeout_ms` is no longer supported
2. **Fixed timeout configuration** - `request_timeout_ms` must be larger than `session_timeout_ms`
3. **Enhanced error handling** - Better connection timeout and retry mechanisms
4. **Improved batching logic** - Optimized producer batching for AutoMQ's object storage architecture

### Message Batching

The Python client automatically batches messages based on:
- **Size threshold**: 1MB batch size
- **Time threshold**: 100ms linger time
- **Manual flush**: `producer.flush()` forces immediate send

This batching mechanism significantly improves throughput when sending multiple messages.