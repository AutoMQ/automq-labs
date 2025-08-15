#!/bin/bash

# Simplified AutoMQ C++ message sending and receiving example script
# Run message sending and receiving functionality directly, without complex parameter processing

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default environment variables
export BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-"localhost:9092"}
export TOPIC_NAME=${TOPIC_NAME:-"automq-cpp-example-topic"}
export CONSUMER_GROUP_ID=${CONSUMER_GROUP_ID:-"automq-cpp-example-group"}
export MESSAGE_COUNT=${MESSAGE_COUNT:-1000}
export MESSAGE_SIZE=${MESSAGE_SIZE:-1024}

echo "AutoMQ C++ Message Example"
echo "======================"
echo "Bootstrap Servers: $BOOTSTRAP_SERVERS"
echo "Topic: $TOPIC_NAME"
echo "Message Count: $MESSAGE_COUNT"
echo ""

# Find executable file
EXECUTABLE=""
if [ -f "/app/bin/automq-cpp-examples" ]; then
    EXECUTABLE="/app/bin/automq-cpp-examples"
elif [ -f "$SCRIPT_DIR/bin/automq-cpp-examples" ]; then
    EXECUTABLE="$SCRIPT_DIR/bin/automq-cpp-examples"
elif [ -f "$SCRIPT_DIR/automq-cpp-examples" ]; then
    EXECUTABLE="$SCRIPT_DIR/automq-cpp-examples"
else
    echo "Error: Executable file not found, please compile the project first"
    echo "Run: make all"
    exit 1
fi

echo "Using executable: $EXECUTABLE"
echo ""

# Create log directory
mkdir -p logs

# Run simple message example directly
echo "Starting message example..."
"$EXECUTABLE" simple 2>&1 | tee "logs/automq-cpp-examples-$(date +%Y%m%d-%H%M%S).log"

if [ $? -eq 0 ]; then
    echo ""
    echo "Message example completed successfully!"
else
    echo ""
    echo "Error: Message example failed"
    exit 1
fi