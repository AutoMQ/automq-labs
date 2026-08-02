#!/bin/bash
# Quick test to verify JMX exporters and metrics collection

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "Quick Metrics Test"
echo "=========================================="

# Check if JMX exporters are responding
echo "Checking JMX exporters..."
for port in 5556 5557 5558; do
    if curl -s http://localhost:$port/metrics | grep -q "jvm_memory"; then
        echo "✓ JMX exporter on port $port is working"
    else
        echo "✗ JMX exporter on port $port is NOT working"
        exit 1
    fi
done

# Check if Prometheus is scraping
echo ""
echo "Checking Prometheus..."
if curl -s http://localhost:9090/api/v1/targets | grep -q "automq-broker"; then
    echo "✓ Prometheus is configured"
else
    echo "✗ Prometheus configuration issue"
    exit 1
fi

# Check if Grafana is ready
echo ""
echo "Checking Grafana..."
if curl -s -f http://localhost:3000/api/health > /dev/null 2>&1; then
    echo "✓ Grafana is ready"
else
    echo "✗ Grafana is not ready"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ All monitoring components are working"
echo "=========================================="
