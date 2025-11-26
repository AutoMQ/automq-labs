#!/bin/bash

# AutoMQ Kafka Client Examples Runner for Go
# This script runs both Simple and Transactional message examples
# Note: Binary should be pre-built (e.g., in Docker container)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== AutoMQ Kafka Client Examples Runner (Go) ==="
echo "Project directory: $PROJECT_DIR"

# Check if the binary exists
BINARY_PATH="$PROJECT_DIR/automq-go-examples"
if [ ! -f "$BINARY_PATH" ]; then
    echo "Error: Could not find the automq-go-examples binary at $BINARY_PATH"
    echo "Please ensure the project is built (e.g., using Docker or 'go build')"
    exit 1
fi

echo "Using binary: $BINARY_PATH"

# Function to run example with error handling
run_example() {
    local example_type=$1
    local example_name=$2
    
    echo ""
    echo "=== Running $example_name ==="
    echo "Type: $example_type"
    echo "Starting at: $(date)"
    
    "$BINARY_PATH" -example="$example_type"
    
    if [ $? -eq 0 ]; then
        echo "$example_name completed successfully at: $(date)"
    else
        echo "Error: $example_name failed at: $(date)"
        return 1
    fi
}

# Run Simple Message Example
run_example "simple" "Simple Message Example"

echo ""
echo "Waiting 1 second before running next example..."
sleep 1

# Run Transactional Message Example
run_example "transactional" "Transactional Message Example"

echo ""
echo "=== All examples completed ==="
echo "Finished at: $(date)"