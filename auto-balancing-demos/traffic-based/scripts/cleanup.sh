#!/bin/bash
# Cleanup script - stop all containers and remove volumes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================="
echo "Cleaning Up Traffic-Based Demo"
echo "========================================="
echo ""

cd "$DEMO_DIR"

echo "Stopping containers..."
docker compose down

echo ""
read -p "Remove volumes? This will delete all data (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing volumes..."
    docker compose down -v
    echo "✓ Volumes removed"
else
    echo "Volumes preserved"
fi

echo ""
echo "========================================="
echo "✓ Cleanup Complete"
echo "========================================="
echo ""
