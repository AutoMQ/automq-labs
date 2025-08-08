# AutoMQ C++ Client Examples Dockerfile
FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV BOOTSTRAP_SERVERS=kafka:9092
ENV TOPIC_NAME=automq-cpp-example-topic
ENV MESSAGE_COUNT=1000
ENV MESSAGE_SIZE=1024

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    make \
    librdkafka-dev \
    librdkafka1 \
    pkg-config \
    uuid-dev \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy source code
COPY src/ ./src/
COPY Makefile .

# Build the application with librdkafka support
RUN make with-kafka

# Create logs directory
RUN mkdir -p logs

# Copy run script
COPY run-examples.sh ./bin/
RUN chmod +x ./bin/run-examples.sh

# Set the default command
CMD ["./bin/run-examples.sh"]