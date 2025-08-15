# AutoMQ C++ Client Examples

This project demonstrates how to use AutoMQ (Apache Kafka) with C++ clients, featuring simple message examples.

## Features

- **Simple Message Example**: Basic producer and consumer with performance metrics
- **Performance Tuning**: Optimized configurations for AutoMQ
- **Docker Support**: Easy deployment with Docker Compose
- **Comprehensive Metrics**: Detailed performance and latency measurements

## Prerequisites

### System Requirements
- macOS, Linux, or Windows (with WSL)
- C++11 compatible compiler (GCC 4.8+ or Clang 3.3+)
- Make build system

### Dependencies

#### For Demo Version (Simulation)
- Standard C++ libraries only
- No external dependencies required

#### For Real Kafka Integration
- **librdkafka**: High-performance C/C++ library for Apache Kafka

#### Installation on macOS
```bash
# Install Xcode Command Line Tools (if not already installed)
xcode-select --install

# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install librdkafka
brew install librdkafka
```

#### Installation on Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install build-essential librdkafka-dev
```

#### Installation on CentOS/RHEL
```bash
sudo yum install gcc-c++ make librdkafka-devel
# or for newer versions:
sudo dnf install gcc-c++ make librdkafka-devel
```

## Quick Start

### 1. Clone and Build

```bash
# Navigate to the cpp directory
cd /path/to/automq-labs/client-examples/cpp

# Build demo version (no Kafka required)
make all

# Or build with real Kafka support (requires librdkafka)
make with-kafka
```

### 2. Run Examples

#### Demo Version (Simulation)
```bash
# Run all examples
./bin/automq-cpp-examples

# Run specific example
./bin/automq-cpp-examples simple

# Or use the runner script
./run-examples.sh
```

#### With Real Kafka
```bash
# Start Kafka with Docker Compose
docker-compose up -d

# Run examples
BOOTSTRAP_SERVERS=localhost:9092 ./bin/automq-cpp-examples

# Or use the runner script
BOOTSTRAP_SERVERS=localhost:9092 ./run-examples.sh
```

### 3. Docker Deployment

```bash
# Start everything with Docker Compose
docker-compose up --build

# Or build and run manually
docker build -t automq-cpp-examples .
docker run --rm automq-cpp-examples
```

## Configuration

### Environment Variables

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `BOOTSTRAP_SERVERS` | Kafka bootstrap servers | `localhost:9092` |
| `TOPIC_NAME` | Topic name for examples | `automq-cpp-example-topic` |
| `CONSUMER_GROUP_ID` | Consumer group ID | `automq-cpp-example-group` |
| `MESSAGE_COUNT` | Number of messages to produce/consume | `10000` |
| `MESSAGE_SIZE` | Size of each message in bytes | `1024` |
| `BATCH_SIZE` | Producer batch size | `65536` |
| `LINGER_MS` | Producer linger time | `100` |
| `BUFFER_MEMORY` | Producer buffer memory | `67108864` (64MB) |
| `MAX_REQUEST_SIZE` | Maximum request size | `10485760` (10MB) |


### Example Usage

```bash
# Custom configuration
MESSAGE_COUNT=5000 MESSAGE_SIZE=2048 ./bin/automq-cpp-examples simple

# Connect to remote Kafka
BOOTSTRAP_SERVERS=kafka.example.com:9092 ./run-examples.sh


```

## Examples Description

### Simple Message Example

Demonstrates basic Kafka producer and consumer functionality:

- **Producer**: Sends messages with configurable batch size and linger time
- **Consumer**: Consumes messages with automatic offset management
- **Metrics**: Tracks throughput, latency, and performance statistics
- **Concurrency**: Producer and consumer run in parallel threads

**Key Features:**
- High-throughput message production
- Efficient batch processing
- Real-time performance monitoring
- Configurable message size and count



## Performance Tuning for AutoMQ

This project includes optimized configurations for AutoMQ:

```cpp
// Producer optimizations
batch.size = 65536          // Larger batches for better throughput
linger.ms = 100             // Balanced latency vs throughput
buffer.memory = 67108864    // 64MB buffer for high throughput
max.request.size = 10485760 // 10MB max request size

// Consumer optimizations
max.poll.records = 1000     // Process more records per poll
fetch.min.bytes = 1024      // Minimum fetch size
fetch.max.wait.ms = 1000    // Maximum wait time for fetch
```

**Why these settings work well with AutoMQ:**
- AutoMQ writes directly to object storage, not local disks
- Larger batches reduce object storage API calls
- Higher buffer memory accommodates burst traffic
- Optimized fetch settings improve consumer efficiency

For more details, see [AutoMQ Performance Tuning Guide](https://www.automq.com/docs/automq/configuration/performance-tuning-for-client).

## Project Structure

```
cpp/
├── src/
│   ├── AutoMQExampleConstants.h      # Configuration constants
│   ├── AutoMQExampleConstants.cpp    # Configuration implementation
│   ├── SimpleMessageExample.h        # Simple example header
│   ├── SimpleMessageExample.cpp      # Simple example implementation

│   └── main.cpp                      # Main application entry point
├── bin/                              # Compiled binaries (created by build)
├── obj/                              # Object files (created by build)
├── logs/                             # Log files (created at runtime)
├── Makefile                          # Build configuration
├── Dockerfile                        # Docker image definition
├── docker-compose.yml                # Docker Compose configuration
├── run-examples.sh                   # Example runner script
└── README.md                         # This file
```

## Build Targets

```bash
# Build demo version (simulation only)
make all

# Build with librdkafka support
make with-kafka

# Install dependencies (macOS)
make install-deps

# Clean build artifacts
make clean

# Run examples
make run
make run-simple


# Docker operations
make docker-build
make docker-run
make docker-compose-up
make docker-compose-down

# Show help
make help
```

## Troubleshooting

### Common Issues

1. **librdkafka not found**
   ```bash
   # Install librdkafka
   brew install librdkafka  # macOS
   sudo apt-get install librdkafka-dev  # Ubuntu
   ```

2. **Compilation errors**
   ```bash
   # Ensure C++11 support
   g++ --version
   # Update if necessary
   ```

3. **Kafka connection issues**
   ```bash
   # Check Kafka is running
   docker-compose ps
   
   # Check connectivity
   telnet localhost 9092
   ```

4. **Permission denied on run-examples.sh**
   ```bash
   chmod +x run-examples.sh
   ```

### Debug Mode

```bash
# Build with debug symbols
make CXXFLAGS="-g -O0 -DDEBUG" all

# Run with verbose output
DEBUG=1 ./run-examples.sh
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is part of the AutoMQ Labs examples and follows the same license terms.

## Resources

- [AutoMQ Documentation](https://www.automq.com/docs)
- [AutoMQ Performance Tuning](https://www.automq.com/docs/automq/configuration/performance-tuning-for-client)
- [librdkafka Documentation](https://github.com/edenhill/librdkafka)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)

## Support

For questions and support:
- [AutoMQ Community](https://www.automq.com/community)
- [GitHub Issues](https://github.com/AutoMQ/automq-labs/issues)
- [AutoMQ Documentation](https://www.automq.com/docs)