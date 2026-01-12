# Scenario: Metrics Monitoring with VictoriaMetrics

This scenario demonstrates how to monitor AutoMQ Table Topic using VictoriaMetrics and Grafana.

## Architecture

```
AutoMQ (Prometheus Endpoint :9090) → VictoriaMetrics (Pull) → Grafana
```

## Getting Started

Before we begin, make sure the environment is up by running `just up` from the playground root.

### Step 1: Start Monitoring Stack

```bash
just -f metrics-scenario/justfile up
```

This will start:
- VictoriaMetrics on port 8428
- Grafana on port 3000

### Step 2: Access Grafana Dashboard

Open Grafana: http://localhost:3000/d/table-topic-dashboard/

### Step 3: Explore Metrics

Query metrics directly:

```bash
# List available metrics
just -f metrics-scenario/justfile list-metrics

# Query specific metric
just -f metrics-scenario/justfile query kafka_tabletopic_delay_milliseconds
```

### Step 4: Cleanup

```bash
just -f metrics-scenario/justfile down
```

## Dashboard Overview

The Table Topic Dashboard provides three views:

### Hardware Health
- CPU and JVM Heap utilization gauges
- CPU & Memory trend over time

### Cluster Overview
- Brokers, Topics, Partitions count
- Table Worker Busy % - event loop utilization
- Request Rate (Produce/Fetch)
- Message Rate by Topic
- S3 Network I/O (Inbound/Outbound)

### Topic View
- Table Topic Delay - latency from Kafka to Iceberg
- Fields Per Second - throughput metric
- Topic Message Rate
- Partition Message Rate
- Partition Offset

## Key Metrics

| Metric | Description |
|--------|-------------|
| `kafka_tableworker_eventloop_busy_ratio_percent` | Table worker event loop busy ratio |
| `kafka_tabletopic_delay_milliseconds` | Delay from Kafka to Iceberg by topic |
| `kafka_tabletopic_fps_fields_per_second` | Fields per second by topic |

## Troubleshooting

### Metrics not showing

1. Check AutoMQ metrics endpoint:
   ```bash
   curl http://localhost:9090/metrics | head -20
   ```

2. Verify VictoriaMetrics targets:
   ```bash
   just -f metrics-scenario/justfile status
   ```

## References

- [AutoMQ Prometheus Integration](https://www.automq.com/docs/automq/observability/integrating-metrics-with-prometheus)
- [VictoriaMetrics Documentation](https://docs.victoriametrics.com/)
