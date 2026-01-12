# QPS-Based Auto-Balancing Demo

This demonstration showcases AutoMQ's ability to detect and correct QPS (queries per second) imbalances. When some brokers receive significantly more requests per second than others due to high-frequency small messages, the auto-balancer automatically redistributes partitions to balance the request rate.

## Scenario

High QPS can overload a broker even if the total byte volume is low. This demo simulates a scenario where one broker receives many small messages (16 bytes each), creating a QPS hotspot.

## What This Demo Shows

1. **Initial Imbalance**: High-frequency small messages create QPS hotspot on Broker 0
2. **Detection**: Auto-balancer detects QPS imbalance through MessagesInPerSec metrics
3. **Rebalancing**: Partitions are migrated to distribute request load evenly
4. **Result**: Request rate is balanced across all brokers

## Quick Start

```bash
./scripts/setup.sh
./scripts/generate-load.sh
./scripts/collect-metrics.sh before
./scripts/verify-balance.sh
./scripts/collect-metrics.sh after
./scripts/cleanup.sh
```

## Key Differences from Traffic-Based Demo

- **Record Size**: 16 bytes (vs 10KB in traffic demo)
- **Record Count**: 500,000 (vs 100,000)
- **Focus Metric**: MessagesInPerSec (vs BytesInPerSec)
- **Imbalance Type**: Request rate hotspot (vs bandwidth hotspot)

## Expected Results

**Before Balancing:**
- Broker 0: High MessagesInPerSec (e.g., 10,000 msg/s)
- Broker 1: Low MessagesInPerSec (e.g., 1,000 msg/s)
- Broker 2: Low MessagesInPerSec (e.g., 1,000 msg/s)

**After Balancing:**
- All brokers: ~4,000 msg/s each
- Low standard deviation

## Related

- GitHub Issue: [#33](https://github.com/AutoMQ/automq-labs/issues/33)
- [Back to main README](../README.md)
