#!/bin/bash

# AutoMQ C++ Client Examples Runner Script
# This script runs the C++ Kafka client examples
# Note: Executable should be pre-built (e.g., in Docker container)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
BOOTSTRAP_SERVERS=${BOOTSTRAP_SERVERS:-"localhost:9092"}
TOPIC_NAME=${TOPIC_NAME:-"automq-cpp-example-topic"}
CONSUMER_GROUP_ID=${CONSUMER_GROUP_ID:-"automq-cpp-example-group"}
MESSAGE_COUNT=${MESSAGE_COUNT:-1000}
MESSAGE_SIZE=${MESSAGE_SIZE:-1024}
EXAMPLE_TYPE=${EXAMPLE_TYPE:-"simple"}

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to find the executable
find_executable() {
    # Check if the executable exists
    if [ -f "/app/bin/automq-cpp-examples" ]; then
        echo "/app/bin/automq-cpp-examples"
    elif [ -f "$PROJECT_DIR/bin/automq-cpp-examples" ]; then
        echo "$PROJECT_DIR/bin/automq-cpp-examples"
    elif [ -f "$PROJECT_DIR/automq-cpp-examples" ]; then
        echo "$PROJECT_DIR/automq-cpp-examples"
    else
        return 1
    fi
}

# Function to run example with error handling
run_example() {
    local example_type=$1
    local example_name=$2
    
    echo ""
    echo "=== Running $example_name ==="
    echo "Type: $example_type"
    echo "Starting at: $(date)"
    
    # Set environment variables
    export BOOTSTRAP_SERVERS
    export TOPIC_NAME
    export CONSUMER_GROUP_ID
    export MESSAGE_COUNT
    export MESSAGE_SIZE
    
    # Find the executable
    EXECUTABLE=$(find_executable)
    if [ $? -ne 0 ]; then
        print_error "Executable not found. Please build the project first."
        print_info "Run: make all to build the project"
        exit 1
    fi
    
    print_info "Using executable: $EXECUTABLE"
    
    # Create logs directory
    mkdir -p logs
    
    # Run the example
    "$EXECUTABLE" "$example_type" 2>&1 | tee "logs/automq-cpp-examples-$(date +%Y%m%d-%H%M%S).log"
    
    if [ $? -eq 0 ]; then
        echo "$example_name completed successfully at: $(date)"
    else
        echo "Error: $example_name failed at: $(date)"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "AutoMQ C++ Client Examples Runner"
    echo ""
    echo "Usage: $0 [example_type]"
    echo ""
    echo "Example types:"
    echo "  simple      - Simple message producer and consumer example"
    echo "  transaction - Transactional message example"
    echo "  all         - Run all examples (default)"
    echo ""
    echo "Environment variables:"
    echo "  BOOTSTRAP_SERVERS   - Kafka bootstrap servers (default: localhost:9092)"
    echo "  TOPIC_NAME          - Topic name (default: automq-cpp-example-topic)"
    echo "  CONSUMER_GROUP_ID   - Consumer group ID (default: automq-cpp-example-group)"
    echo "  MESSAGE_COUNT       - Number of messages (default: 1000)"
    echo "  MESSAGE_SIZE        - Message size in bytes (default: 1024)"
    echo ""
    echo "Examples:"
    echo "  $0 simple"
    echo "  MESSAGE_COUNT=5000 $0 transaction"
    echo "  BOOTSTRAP_SERVERS=kafka:9092 $0 all"
}

# Main execution
main() {
    local example_type=${1:-$EXAMPLE_TYPE}
    
    if [ "$example_type" = "help" ] || [ "$example_type" = "-h" ] || [ "$example_type" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    print_info "AutoMQ C++ Client Examples"
    print_info "==========================="
    
    # Check Kafka connectivity (optional)
    if ! check_kafka_connectivity; then
        print_warning "Kafka connectivity check failed, but continuing anyway..."
        print_info "Make sure Kafka is running and accessible at $BOOTSTRAP_SERVERS"
    fi
    
    # Create topic
    create_topic
    
    # Run examples
    run_examples "$example_type"
    
    print_success "All done!"
}

# Execute main function with all arguments
main "$@"