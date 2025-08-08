#!/bin/bash

# AutoMQ C++ Client Examples Runner Script

set -e

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
EXAMPLE_TYPE=${EXAMPLE_TYPE:-"all"}

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

# Function to check if Kafka is available
check_kafka_connectivity() {
    print_info "Checking Kafka connectivity..."
    
    # Simple connectivity check (this would require kafka tools in real scenario)
    # For demo purposes, we'll just check if the bootstrap server is reachable
    if command -v nc >/dev/null 2>&1; then
        if echo "" | nc -w 5 ${BOOTSTRAP_SERVERS%:*} ${BOOTSTRAP_SERVERS#*:} >/dev/null 2>&1; then
            print_success "Kafka is reachable at $BOOTSTRAP_SERVERS"
            return 0
        else
            print_warning "Cannot reach Kafka at $BOOTSTRAP_SERVERS"
            return 1
        fi
    else
        print_warning "netcat (nc) not available, skipping connectivity check"
        return 0
    fi
}

# Function to create topic (simulation)
create_topic() {
    print_info "Creating topic: $TOPIC_NAME"
    
    # In a real scenario, you would use kafka-topics.sh or similar
    # For demo purposes, we'll just simulate this
    print_info "Topic creation simulated (in real scenario, use kafka-topics.sh)"
    print_success "Topic '$TOPIC_NAME' is ready"
}

# Function to run the examples
run_examples() {
    local example_type=$1
    
    print_info "Starting AutoMQ C++ Client Examples"
    print_info "Configuration:"
    echo "  Bootstrap Servers: $BOOTSTRAP_SERVERS"
    echo "  Topic Name: $TOPIC_NAME"
    echo "  Consumer Group: $CONSUMER_GROUP_ID"
    echo "  Message Count: $MESSAGE_COUNT"
    echo "  Message Size: $MESSAGE_SIZE bytes"
    echo "  Example Type: $example_type"
    echo ""
    
    # Set environment variables
    export BOOTSTRAP_SERVERS
    export TOPIC_NAME
    export CONSUMER_GROUP_ID
    export MESSAGE_COUNT
    export MESSAGE_SIZE
    
    # Check if the executable exists
    if [ -f "/app/bin/automq-cpp-examples" ]; then
        EXECUTABLE="/app/bin/automq-cpp-examples"
    elif [ -f "./bin/automq-cpp-examples" ]; then
        EXECUTABLE="./bin/automq-cpp-examples"
    elif [ -f "./automq-cpp-examples" ]; then
        EXECUTABLE="./automq-cpp-examples"
    else
        print_error "Executable not found. Please build the project first."
        print_info "Run: make all (for demo) or make with-kafka (for real Kafka)"
        exit 1
    fi
    
    print_info "Running examples with: $EXECUTABLE"
    
    # Create logs directory
    mkdir -p logs
    
    # Run the examples
    if $EXECUTABLE "$example_type" 2>&1 | tee "logs/automq-cpp-examples-$(date +%Y%m%d-%H%M%S).log"; then
        print_success "Examples completed successfully!"
    else
        print_error "Examples failed with exit code $?"
        exit 1
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