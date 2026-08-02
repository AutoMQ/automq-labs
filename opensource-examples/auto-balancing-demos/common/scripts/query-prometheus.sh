#!/bin/bash
# Query Prometheus API and return results
# Usage: ./query-prometheus.sh <query> [prometheus_url]

set -e

QUERY=$1
PROMETHEUS_URL=${2:-"http://localhost:9090"}

if [ -z "$QUERY" ]; then
    echo "Usage: $0 <query> [prometheus_url]"
    exit 1
fi

# URL encode the query
ENCODED_QUERY=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$QUERY'))")

# Query Prometheus
response=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=${ENCODED_QUERY}")

# Check if query was successful
status=$(echo "$response" | jq -r '.status')
if [ "$status" != "success" ]; then
    echo "Prometheus query failed:"
    echo "$response" | jq '.'
    exit 1
fi

# Return the result
echo "$response" | jq '.data.result'
