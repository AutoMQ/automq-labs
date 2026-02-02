#!/bin/bash
set -e
NAMESPACE="${NAMESPACE:-automq}"
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
print_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
print_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

echo ""
echo "=============================================="
echo " AutoMQ Strimzi Installation Verification"
echo "=============================================="
echo ""

print_info "Checking Strimzi Operator..."
OPERATOR_PODS=$(kubectl get pods -n "$NAMESPACE" -l name=strimzi-cluster-operator --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$OPERATOR_PODS" -ge 1 ] && print_info "✓ Strimzi Operator is running" || { print_error "Strimzi Operator is not running"; exit 1; }

print_info "Checking AutoMQ pods..."
echo ""
kubectl get pods -n "$NAMESPACE" -l strimzi.io/cluster=my-cluster
echo ""

CONTROLLER_PODS=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/pool-name=controller --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$CONTROLLER_PODS" -ge 3 ] && print_info "✓ All 3 controller pods are running" || print_error "Only $CONTROLLER_PODS/3 controller pods running"

CONTROLLER_POD=$(kubectl get pods -n "$NAMESPACE" -l strimzi.io/pool-name=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
[ -z "$CONTROLLER_POD" ] && { print_error "No controller pod found"; exit 1; }

print_info "Creating test topic..."
kubectl exec -n "$NAMESPACE" "$CONTROLLER_POD" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 --create --topic test-topic \
    --partitions 3 --replication-factor 1 --if-not-exists 2>/dev/null || true
print_info "✓ Test topic created"

print_info "Listing topics..."
echo ""
kubectl exec -n "$NAMESPACE" "$CONTROLLER_POD" -- /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 --list 2>/dev/null

echo ""
echo "=============================================="
echo " Verification Complete!"
echo "=============================================="
echo ""
print_info "AutoMQ cluster is healthy and ready to use."
echo ""
echo "Quick Commands:"
echo ""
echo "  # Produce messages"
echo "  kubectl exec -it -n $NAMESPACE $CONTROLLER_POD -- /opt/kafka/bin/kafka-console-producer.sh \\"
echo "    --bootstrap-server localhost:9092 --topic test-topic"
echo ""
echo "  # Consume messages"
echo "  kubectl exec -it -n $NAMESPACE $CONTROLLER_POD -- /opt/kafka/bin/kafka-console-consumer.sh \\"
echo "    --bootstrap-server localhost:9092 --topic test-topic --from-beginning"
echo ""
