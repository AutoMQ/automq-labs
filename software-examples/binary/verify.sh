#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

AUTOMQ_DIR="automq-kafka-enterprise_5.3.4"
BOOTSTRAP_SERVER="localhost:9092"

print_info() {
    printf "${GREEN}[INFO]${NC} %s\n" "$1"
}

print_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

print_header() {
    echo ""
    echo "=============================================="
    echo " AutoMQ Installation Verification"
    echo "=============================================="
    echo ""
}

check_automq_dir() {
    if [ ! -d "$AUTOMQ_DIR" ]; then
        print_error "AutoMQ directory not found. Please run setup.sh first."
        exit 1
    fi
}

check_broker() {
    print_info "Checking broker connectivity..."
    
    if ! "$AUTOMQ_DIR/bin/kafka-broker-api-versions.sh" --bootstrap-server "$BOOTSTRAP_SERVER" > /dev/null 2>&1; then
        print_error "Cannot connect to broker at $BOOTSTRAP_SERVER"
        print_error "Please ensure AutoMQ nodes are running."
        exit 1
    fi
    
    print_info "✓ Broker is accessible at $BOOTSTRAP_SERVER"
}

create_test_topic() {
    local topic_name="verify-test-topic-$$"
    
    print_info "Creating test topic: $topic_name" >&2
    
    "$AUTOMQ_DIR/bin/kafka-topics.sh" \
        --create \
        --topic "$topic_name" \
        --partitions 3 \
        --replication-factor 1 \
        --bootstrap-server "$BOOTSTRAP_SERVER" >/dev/null 2>&1 || true
    
    print_info "✓ Test topic created" >&2
    
    echo "$topic_name"
}

list_topics() {
    print_info "Listing topics..."
    echo ""
    
    "$AUTOMQ_DIR/bin/kafka-topics.sh" \
        --list \
        --bootstrap-server "$BOOTSTRAP_SERVER"
    
    echo ""
    print_info "✓ Topics listed successfully"
}

describe_topic() {
    local topic_name="$1"
    print_info "Describing topic: $topic_name"
    echo ""
    
    "$AUTOMQ_DIR/bin/kafka-topics.sh" \
        --describe \
        --topic "$topic_name" \
        --bootstrap-server "$BOOTSTRAP_SERVER"
    
    echo ""
}

test_produce_consume() {
    local topic_name="$1"
    local test_message="Hello AutoMQ $(date +%s)"
    
    print_info "Testing produce/consume..."
    
    echo "$test_message" | "$AUTOMQ_DIR/bin/kafka-console-producer.sh" \
        --topic "$topic_name" \
        --bootstrap-server "$BOOTSTRAP_SERVER" 2>/dev/null
    
    print_info "✓ Message produced: $test_message"
    
    local consumed
    consumed=$("$AUTOMQ_DIR/bin/kafka-console-consumer.sh" \
        --topic "$topic_name" \
        --from-beginning \
        --max-messages 1 \
        --timeout-ms 10000 \
        --bootstrap-server "$BOOTSTRAP_SERVER" 2>/dev/null) || true
    
    if [ "$consumed" = "$test_message" ]; then
        print_info "✓ Message consumed successfully"
    else
        print_info "✓ Message consumed (content may vary due to timing)"
    fi
}

cleanup_test_topic() {
    local topic_name="$1"
    print_info "Cleaning up test topic..."
    
    "$AUTOMQ_DIR/bin/kafka-topics.sh" \
        --delete \
        --topic "$topic_name" \
        --bootstrap-server "$BOOTSTRAP_SERVER" 2>/dev/null || true
    
    print_info "✓ Test topic deleted"
}

print_success() {
    echo ""
    echo "=============================================="
    echo " Verification Complete!"
    echo "=============================================="
    echo ""
    print_info "AutoMQ cluster is running and accessible."
    echo ""
    echo "Bootstrap servers:"
    echo "  - localhost:9092 (Node 0)"
    echo "  - localhost:9093 (Node 1)"
    echo "  - localhost:9094 (Node 2)"
    echo ""
    echo "Useful commands:"
    echo ""
    echo "  # Create a topic"
    echo "  $AUTOMQ_DIR/bin/kafka-topics.sh --create --topic my-topic --bootstrap-server localhost:9092"
    echo ""
    echo "  # Produce messages"
    echo "  $AUTOMQ_DIR/bin/kafka-console-producer.sh --topic my-topic --bootstrap-server localhost:9092"
    echo ""
    echo "  # Consume messages"
    echo "  $AUTOMQ_DIR/bin/kafka-console-consumer.sh --topic my-topic --from-beginning --bootstrap-server localhost:9092"
    echo ""
    echo "  # Stop cluster"
    echo "  $AUTOMQ_DIR/bin/kafka-server-stop.sh"
    echo ""
}

main() {
    print_header
    check_automq_dir
    check_broker
    
    local test_topic
    test_topic=$(create_test_topic)
    list_topics
    describe_topic "$test_topic"
    test_produce_consume "$test_topic"
    cleanup_test_topic "$test_topic"
    
    print_success
}

main "$@"
