#!/bin/bash
# Wait for a Docker container to be healthy
# Usage: ./wait-for-container.sh <container_name> [timeout_seconds]

set -e

CONTAINER_NAME=$1
TIMEOUT=${2:-300}  # Default 5 minutes
INTERVAL=5

if [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <container_name> [timeout_seconds]"
    exit 1
fi

echo "Waiting for container '$CONTAINER_NAME' to be healthy (timeout: ${TIMEOUT}s)..."

elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    # Check if container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Container '$CONTAINER_NAME' does not exist"
        exit 1
    fi
    
    # Check container status
    status=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
    
    if [ "$status" = "running" ]; then
        # Check health status if health check is configured
        health=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "none")
        
        if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
            echo "✓ Container '$CONTAINER_NAME' is ready"
            exit 0
        else
            echo "Container '$CONTAINER_NAME' is running but not healthy yet (status: $health)..."
        fi
    else
        echo "Container '$CONTAINER_NAME' status: $status"
    fi
    
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

echo "✗ Timeout waiting for container '$CONTAINER_NAME'"
exit 1
