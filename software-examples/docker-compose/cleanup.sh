#!/bin/bash
# AutoMQ Software Cleanup Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           AutoMQ Software - Cluster Cleanup                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Confirmation prompt
read -p "This will remove all AutoMQ containers and data. Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Cleanup cancelled"
    exit 0
fi

echo ""

# Step 1: Stop and remove containers
print_step "Step 1/3: Stopping and removing containers..."

docker compose down -v 2>/dev/null || docker-compose down -v
print_success "Containers stopped and removed"

echo ""

# Step 2: Remove network
print_step "Step 2/3: Removing network..."

docker network rm automq_net 2>/dev/null || true
print_success "Network removed"

echo ""

# Step 3: Clean up dangling resources (optional)
print_step "Step 3/3: Cleaning up resources..."

# Remove any orphaned volumes
docker volume prune -f --filter "label=com.docker.compose.project=docker-compose" 2>/dev/null || true
print_success "Resources cleaned up"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    Cleanup Complete                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  All AutoMQ resources have been removed."
echo "  Run ./install.sh to deploy a fresh cluster."
echo ""
