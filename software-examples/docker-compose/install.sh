#!/bin/bash
# AutoMQ Software Docker Compose Installation Script

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

print_error() {
    echo -e "${RED}✗${NC} $1"
}

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AutoMQ Software - Docker Compose Setup             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Prerequisites Check
print_step "Step 1/4: Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_success "Docker is installed"

if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running. Please start Docker."
    exit 1
fi
print_success "Docker daemon is running"

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose."
    exit 1
fi
print_success "Docker Compose is available"

echo ""

# Step 2: Pull Images
print_step "Step 2/4: Pulling container images..."
print_warning "This may take a few minutes on first run..."

docker compose pull 2>/dev/null || docker-compose pull
print_success "Images pulled successfully"

echo ""

# Step 3: Start Services
print_step "Step 3/4: Starting AutoMQ cluster..."

docker compose up -d 2>/dev/null || docker-compose up -d
print_success "Services started"

echo ""

# Step 4: Wait for cluster to be ready
print_step "Step 4/4: Waiting for cluster to be ready..."

MAX_RETRIES=60
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RUNNING_CONTROLLERS=$(docker ps --filter "name=automq-controller" --filter "status=running" --format "{{.Names}}" | wc -l | tr -d ' ')
    
    if [ "$RUNNING_CONTROLLERS" -ge 3 ]; then
        print_success "All 3 controller nodes are running"
        break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo -ne "\r  Waiting for controllers... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo ""

if [ "$RUNNING_CONTROLLERS" -lt 3 ]; then
    print_warning "Not all controllers started. Check logs with: docker compose logs"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Installation Complete                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  AutoMQ Bootstrap Servers:"
echo "    - Internal: controller1:9092,controller2:9092,controller3:9092"
echo "    - External: localhost:19092,localhost:29092,localhost:39092"
echo ""
echo "  MinIO Console: http://localhost:9001"
echo "    - Username: admin"
echo "    - Password: automq_demo_secret"
echo ""
echo "  Next Steps:"
echo "    1. Run ./verify.sh to test the cluster"
echo "    2. Run ./cleanup.sh to remove the cluster"
echo ""
