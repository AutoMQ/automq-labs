# Traffic-Based Auto-Balancing Demo

This demonstration showcases AutoMQ's ability to detect and correct traffic imbalances across brokers. When some brokers handle significantly more traffic (bytes per second) than others, the auto-balancer automatically redistributes partitions to achieve even load distribution.

## Scenario

In real-world deployments, data distribution is often uneven. Some topics or partitions may receive much higher traffic volumes than others, causing certain brokers to become hotspots. This demo simulates such a scenario and shows how AutoMQ's auto-balancer resolves it.

## What This Demo Shows

1. **Initial Imbalance**: High-volume traffic (10KB messages) is directed to partitions primarily located on Broker 0
2. **Detection**: Auto-balancer detects the traffic imbalance through BytesInPerSec metrics
3. **Rebalancing**: Partitions are automatically migrated from the overloaded broker to others
4. **Result**: Traffic is evenly distributed across all three brokers

## Prerequisites

- Docker and Docker Compose installed
- At least 8GB RAM available
- Ports 3000, 8081, 9000-9001, 9090, 9092-9094 available

## Quick Start

```bash
# 1. Start the environment
./scripts/setup.sh

# 2. Generate traffic imbalance
./scripts/generate-load.sh

# 3. Collect "before" metrics
./scripts/collect-metrics.sh before

# 4. Wait for auto-balancer (optional - it runs automatically)
./scripts/verify-balance.sh

# 5. Collect "after" metrics
./scripts/collect-metrics.sh after

# 6. Generate screenshots (optional)
./scripts/generate-screenshots.sh before
./scripts/generate-screenshots.sh after

# 7. Cleanup
./scripts/cleanup.sh
```

## Step-by-Step Guide

### Step 1: Start the Environment

```bash
./scripts/setup.sh
```

This script will:
- Start 3 AutoMQ brokers with auto-balancer enabled
- Start MinIO for S3-compatible storage
- Start Prometheus for metrics collection
- Start Grafana for visualization
- Create a test topic with 6 partitions

**Expected time**: 2-3 minutes

### Step 2: Generate Traffic Imbalance

```bash
./scripts/generate-load.sh
```

This script sends 100,000 messages of 10KB each to the topic, creating a traffic imbalance where most traffic goes to Broker 0.

**Expected time**: 1-2 minutes

### Step 3: Collect Initial Metrics

```bash
./scripts/collect-metrics.sh before
```

This captures the current state showing the imbalance. Results are saved to `results/before-balancing.md`.

**Expected output**:
- Broker 0: High BytesInPerSec (e.g., 50 MB/s)
- Broker 1: Low BytesInPerSec (e.g., 5 MB/s)
- Broker 2: Low BytesInPerSec (e.g., 5 MB/s)
- High standard deviation indicating imbalance

### Step 4: Wait for Auto-Balancer

The auto-balancer runs automatically every 30 seconds. You can monitor its progress:

```bash
./scripts/verify-balance.sh
```

Or check Grafana dashboards at http://localhost:3000

**Expected time**: 2-5 minutes

### Step 5: Collect Final Metrics

```bash
./scripts/collect-metrics.sh after
```

This captures the balanced state. Results are saved to `results/after-balancing.md`.

**Expected output**:
- Broker 0: ~20 MB/s
- Broker 1: ~20 MB/s
- Broker 2: ~20 MB/s
- Low standard deviation indicating balance

### Step 6: Generate Screenshots (Optional)

```bash
./scripts/generate-screenshots.sh before
./scripts/generate-screenshots.sh after
```

Captures Grafana dashboard panels showing the metrics visually.

### Step 7: Cleanup

```bash
./scripts/cleanup.sh
```

Stops all containers. Optionally removes volumes to free disk space.

## Monitoring

### Grafana Dashboards

Access Grafana at http://localhost:3000 (admin/admin)

Key panels:
- **Bytes In Per Second**: Shows traffic volume by broker
- **Bytes Out Per Second**: Shows outbound traffic
- **Partition Count**: Shows partition distribution
- **Latency Metrics**: Shows request latency

### Prometheus

Access Prometheus at http://localhost:9090

Useful queries:
```promql
# Bytes in per second by broker
kafka_server_broker_topic_metrics_bytes_in_per_sec

# Standard deviation of bytes in
stddev(kafka_server_broker_topic_metrics_bytes_in_per_sec)

# Partition count by broker
kafka_server_replica_manager_partition_count
```

### Broker Logs

Check auto-balancer activity:
```bash
docker compose logs server1 | grep autobalancer
```

## Results

After running the demo, you'll find:
- `results/before-balancing.md` - Metrics before auto-balancing
- `results/after-balancing.md` - Metrics after auto-balancing
- `results/screenshots/` - Grafana dashboard screenshots

## Troubleshooting

### Auto-balancer doesn't trigger

Check if it's enabled:
```bash
docker compose logs server1 | grep "autobalancer.controller.enable"
```

Verify metrics are being collected:
```bash
curl http://localhost:9090/api/v1/targets
```

### Containers fail to start

Check Docker resources:
```bash
docker system df
docker stats
```

Ensure ports are available:
```bash
lsof -i :3000,9090,9092
```

### Grafana screenshots fail

Verify Grafana is accessible:
```bash
curl http://localhost:3000/api/health
```

Check renderer logs:
```bash
docker compose logs renderer
```

## Configuration

### Auto-Balancer Settings

Key configuration in `docker-compose.yml`:
```yaml
KAFKA_AUTO_BALANCER_CONTROLLER_ENABLE: "true"
KAFKA_AUTO_BALANCER_CONTROLLER_GOALS: "kafka.autobalancer.goals.NetworkInUsageDistributionGoal,kafka.autobalancer.goals.NetworkOutUsageDistributionGoal"
KAFKA_AUTO_BALANCER_CONTROLLER_ANOMALY_DETECT_INTERVAL_MS: "30000"
```

### Adjusting Detection Sensitivity

To make auto-balancer more/less sensitive, adjust the detection interval:
- Faster: `20000` (20 seconds)
- Slower: `60000` (60 seconds)

## Related Issues

- GitHub Issue: [#32](https://github.com/AutoMQ/automq-labs/issues/32)
- AutoMQ Documentation: https://www.automq.com/docs

## Next Steps

Try other auto-balancing scenarios:
- [QPS-Based Auto-Balancing](../qps-based/)
- [Slow Node Isolation](../slow-node-isolation/)
- [Scale-Up Auto-Balancing](../scale-up/)
- [Scale-Down Auto-Balancing](../scale-down/)
