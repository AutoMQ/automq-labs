# Design Document: AutoMQ Auto-Balancing Demonstrations

## Overview

This design document describes the architecture and implementation approach for five comprehensive AutoMQ auto-balancing demonstration projects. Each demonstration will showcase a specific auto-balancing scenario with real experimental data, automated scripts, and visual monitoring through Grafana dashboards.

The demonstrations will be fully automated, requiring no manual intervention once started. They will generate actual experimental results including metrics, screenshots, and comparison reports.

## Architecture

### High-Level Architecture

```mermaid
graph TB
    subgraph "Demo Environment"
        subgraph "AutoMQ Cluster"
            B1[Broker 1<br/>+ JMX Exporter]
            B2[Broker 2<br/>+ JMX Exporter]
            B3[Broker 3<br/>+ JMX Exporter]
        end
        
        subgraph "Storage"
            MinIO[MinIO<br/>S3-Compatible Storage]
        end
        
        subgraph "Monitoring Stack"
            Prometheus[Prometheus<br/>Metrics Collection]
            Grafana[Grafana<br/>Visualization]
        end
        
        subgraph "Load Generation"
            LoadGen[Load Generator<br/>kafka-producer-perf-test]
        end
    end
    
    subgraph "Automation Scripts"
        Setup[setup.sh]
        GenLoad[generate-load.sh]
        Collect[collect-metrics.sh]
        Screenshot[generate-screenshots.sh]
        Verify[verify-balance.sh]
        Cleanup[cleanup.sh]
    end
    
    B1 --> MinIO
    B2 --> MinIO
    B3 --> MinIO
    
    B1 -->|JMX Metrics| Prometheus
    B2 -->|JMX Metrics| Prometheus
    B3 -->|JMX Metrics| Prometheus
    
    Prometheus --> Grafana
    
    LoadGen -->|Produce Messages| B1
    LoadGen -->|Produce Messages| B2
    LoadGen -->|Produce Messages| B3
    
    Setup -.->|Start| B1
    Setup -.->|Start| B2
    Setup -.->|Start| B3
    Setup -.->|Configure| Grafana
    
    GenLoad -.->|Control| LoadGen
    Collect -.->|Query| Prometheus
    Screenshot -.->|API Call| Grafana
    Verify -.->|Check| Prometheus
    Cleanup -.->|Stop| B1
```

### Component Responsibilities

#### AutoMQ Cluster
- **Brokers**: Handle message production/consumption and storage
- **Auto-Balancer**: Automatically detect imbalances and migrate partitions
- **JMX Exporter**: Export broker metrics to Prometheus format

#### Monitoring Stack
- **Prometheus**: Scrape and store time-series metrics from JMX Exporters
- **Grafana**: Visualize metrics through pre-configured dashboards
- **JMX Exporter**: Sidecar containers that expose Kafka JMX metrics as Prometheus metrics

#### Storage
- **MinIO**: Provide S3-compatible object storage for AutoMQ

#### Automation Scripts
- **setup.sh**: Initialize environment, start containers, configure monitoring
- **generate-load.sh**: Create specific load patterns for each scenario
- **collect-metrics.sh**: Query Prometheus and format metrics into reports
- **generate-screenshots.sh**: Use Grafana API to capture dashboard images
- **verify-balance.sh**: Poll metrics to detect when balancing is complete
- **cleanup.sh**: Stop containers and clean up resources

## Components and Interfaces

### Docker Compose Configuration

Each demo will have a `docker-compose.yml` based on the existing three-node cluster template with additions for monitoring:

```yaml
version: "3.8"

services:
  # MinIO for S3 storage (existing)
  minio:
    image: minio/minio:latest
    # ... existing configuration
  
  # AutoMQ Brokers (existing, with JMX configuration)
  server1:
    image: automqinc/automq:1.6.0
    environment:
      KAFKA_JMX_PORT: 9999
      KAFKA_JMX_HOSTNAME: server1
      # ... existing AutoMQ configuration
      # Auto-balancer configuration
      KAFKA_AUTO_BALANCER_CONTROLLER_ENABLE: "true"
      KAFKA_AUTO_BALANCER_CONTROLLER_GOALS: "kafka.autobalancer.goals.NetworkInUsageDistributionGoal,kafka.autobalancer.goals.NetworkOutUsageDistributionGoal"
      KAFKA_AUTO_BALANCER_CONTROLLER_ANOMALY_DETECT_INTERVAL_MS: "30000"
    depends_on:
      - minio
      - jmx-exporter1
  
  # JMX Exporters (one per broker)
  jmx-exporter1:
    image: bitnami/jmx-exporter:latest
    ports:
      - "5556:5556"
    volumes:
      - ./jmx-exporter-config.yml:/etc/jmx-exporter/config.yml
    command:
      - "5556"
      - "/etc/jmx-exporter/config.yml"
    environment:
      JMX_URL: "service:jmx:rmi:///jndi/rmi://server1:9999/jmxrmi"
  
  # Prometheus
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=2h'
  
  # Grafana
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/datasources:/etc/grafana/provisioning/datasources
      - grafana-data:/var/lib/grafana
    environment:
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"
      GF_RENDERING_SERVER_URL: "http://renderer:8081/render"
      GF_RENDERING_CALLBACK_URL: "http://grafana:3000/"
  
  # Grafana Image Renderer (for screenshots)
  renderer:
    image: grafana/grafana-image-renderer:latest
    ports:
      - "8081:8081"
    environment:
      ENABLE_METRICS: "true"

volumes:
  prometheus-data:
  grafana-data:

networks:
  automq_net:
    driver: bridge
```

### JMX Exporter Configuration

The `jmx-exporter-config.yml` will export key Kafka metrics:

```yaml
lowercaseOutputName: true
lowercaseOutputLabelNames: true

rules:
  # Broker metrics
  - pattern: kafka.server<type=BrokerTopicMetrics, name=(.+)><>Count
    name: kafka_server_broker_topic_metrics_$1_total
    type: COUNTER
  
  - pattern: kafka.server<type=BrokerTopicMetrics, name=(.+)PerSec><>OneMinuteRate
    name: kafka_server_broker_topic_metrics_$1_per_sec
    type: GAUGE
  
  # Network metrics
  - pattern: kafka.network<type=RequestMetrics, name=(.+), request=(.+)><>Mean
    name: kafka_network_request_metrics_$1_mean
    labels:
      request: "$2"
    type: GAUGE
  
  # Partition metrics
  - pattern: kafka.cluster<type=Partition, name=(.+), topic=(.+), partition=(.+)><>Value
    name: kafka_cluster_partition_$1
    labels:
      topic: "$2"
      partition: "$3"
    type: GAUGE
```

### Prometheus Configuration

The `prometheus.yml` will scrape JMX Exporters:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'automq-broker1'
    static_configs:
      - targets: ['jmx-exporter1:5556']
        labels:
          broker: 'server1'
          broker_id: '0'
  
  - job_name: 'automq-broker2'
    static_configs:
      - targets: ['jmx-exporter2:5556']
        labels:
          broker: 'server2'
          broker_id: '1'
  
  - job_name: 'automq-broker3'
    static_configs:
      - targets: ['jmx-exporter3:5556']
        labels:
          broker: 'server3'
          broker_id: '2'
```

### Grafana Dashboard

A pre-configured dashboard will display:
- Bytes In/Out per second by broker
- Messages In/Out per second by broker
- Partition count by broker
- Produce/Fetch latency by broker
- Network request rate by broker

Dashboard JSON will be provisioned automatically on Grafana startup.

## Data Models

### Metrics Data Model

```typescript
interface BrokerMetrics {
  broker_id: string;
  broker_name: string;
  timestamp: number;
  
  // Traffic metrics
  bytes_in_per_sec: number;
  bytes_out_per_sec: number;
  messages_in_per_sec: number;
  
  // Partition metrics
  partition_count: number;
  leader_partition_count: number;
  
  // Latency metrics
  produce_request_mean_ms: number;
  fetch_request_mean_ms: number;
  
  // Network metrics
  request_rate: number;
}

interface ClusterMetrics {
  timestamp: number;
  brokers: BrokerMetrics[];
  
  // Aggregate metrics
  total_bytes_in_per_sec: number;
  total_bytes_out_per_sec: number;
  total_messages_in_per_sec: number;
  total_partitions: number;
  
  // Balance metrics
  bytes_in_std_dev: number;
  bytes_out_std_dev: number;
  messages_in_std_dev: number;
  partition_count_std_dev: number;
}
```

### Results Data Model

```typescript
interface ExperimentResults {
  demo_name: string;
  timestamp: string;
  
  before: {
    metrics: ClusterMetrics;
    partition_distribution: PartitionDistribution;
    screenshots: string[];  // File paths
  };
  
  after: {
    metrics: ClusterMetrics;
    partition_distribution: PartitionDistribution;
    screenshots: string[];
  };
  
  improvement: {
    bytes_in_balance_improvement: number;  // Percentage
    bytes_out_balance_improvement: number;
    messages_in_balance_improvement: number;
    partition_balance_improvement: number;
  };
}

interface PartitionDistribution {
  topic: string;
  partitions: Array<{
    partition_id: number;
    leader_broker: string;
    replicas: string[];
  }>;
}
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Environment Initialization Completeness
*For any* demo execution, when the setup script completes successfully, all required containers (brokers, MinIO, Prometheus, Grafana, JMX Exporters) should be running and healthy.

**Validates: Requirements 1.1, 1.2, 2.1, 3.1, 4.1, 5.1, 6.1, 6.2, 6.3**

### Property 2: Load Generation Creates Measurable Imbalance
*For any* demo scenario, when the load generation script completes, the collected metrics should show a statistically significant imbalance (standard deviation > threshold) in the targeted metric (bytes, messages, or latency).

**Validates: Requirements 1.3, 1.4, 2.2, 2.3, 3.2, 3.3**

### Property 3: Auto-Balancer Convergence
*For any* demo execution, when the auto-balancer runs after detecting imbalance, the system should eventually reach a balanced state where the standard deviation of the targeted metric across brokers is below the threshold.

**Validates: Requirements 1.5, 1.6, 2.4, 2.5, 3.4, 3.5, 4.5, 4.6, 5.5, 5.6**

### Property 4: Metrics Collection Accuracy
*For any* point in time during a demo, when the metrics collection script queries Prometheus, the returned metrics should match the actual state of the cluster (within measurement error bounds).

**Validates: Requirements 1.4, 1.6, 2.3, 2.5, 3.3, 3.5, 4.2, 4.6, 5.2, 5.6, 6.4, 6.5, 6.6**

### Property 5: Screenshot Generation Success
*For any* configured Grafana dashboard panel, when the screenshot generation script executes, it should produce a valid PNG file with non-zero size containing the rendered visualization.

**Validates: Requirements 1.9, 2.8, 3.8, 4.9, 5.9, 6.7, 6.8**

### Property 6: Before/After Improvement
*For any* demo execution, when comparing before and after metrics, the standard deviation of the targeted metric should be lower after auto-balancing than before (demonstrating improvement).

**Validates: Requirements 1.6, 2.5, 3.5, 4.6, 5.6, 8.10**

### Property 7: Script Idempotency
*For any* script that supports idempotent execution (setup, cleanup), running the script multiple times should produce the same end state without errors.

**Validates: Requirements 7.8**

### Property 8: Documentation Completeness
*For any* demo directory, the README.md file should contain all required sections: purpose, prerequisites, step-by-step instructions, expected results, and troubleshooting.

**Validates: Requirements 8.1, 8.2, 8.3, 8.4, 10.3**

### Property 9: Results File Generation
*For any* demo execution that completes successfully, the results directory should contain before-balancing.md, after-balancing.md, metrics-comparison.md, and at least one screenshot in the screenshots/ subdirectory.

**Validates: Requirements 8.5, 8.6, 8.7, 8.8, 8.9, 8.10, 10.4**

### Property 10: AutoMQ Configuration Validity
*For any* demo docker-compose.yml file, the AutoMQ broker configuration should include auto-balancer enabled, valid goal list, and appropriate detection interval.

**Validates: Requirements 9.1, 9.2, 9.3, 9.4, 9.5, 9.7**

## Error Handling

### Container Startup Failures
- **Detection**: Health checks and readiness probes
- **Handling**: Retry with exponential backoff (max 3 attempts)
- **Logging**: Output container logs for debugging
- **Recovery**: Clean up and restart from scratch if all retries fail

### Auto-Balancer Not Triggering
- **Detection**: Poll metrics for configurable timeout (default 5 minutes)
- **Handling**: Check auto-balancer logs, verify configuration
- **Logging**: Output relevant broker logs and configuration
- **Recovery**: Suggest manual verification steps in output

### Grafana Screenshot Failures
- **Detection**: HTTP error codes or empty file
- **Handling**: Retry with different parameters (resolution, timeout)
- **Fallback**: Generate text-based reports if screenshots fail
- **Logging**: Output Grafana API response for debugging

### Prometheus Query Failures
- **Detection**: HTTP errors or invalid JSON responses
- **Handling**: Retry with exponential backoff
- **Fallback**: Use docker exec to query JMX directly
- **Logging**: Output query and error details

### Load Generation Failures
- **Detection**: Non-zero exit code from kafka-producer-perf-test
- **Handling**: Verify broker connectivity, check topic existence
- **Recovery**: Recreate topic and retry
- **Logging**: Output full error message and broker status

## Testing Strategy

### Unit Testing
- Test individual script functions (metric parsing, calculation, formatting)
- Test configuration file generation
- Test error handling logic
- Mock external dependencies (Prometheus, Grafana APIs)

### Integration Testing
- Test full demo execution end-to-end
- Verify all containers start successfully
- Verify metrics are collected correctly
- Verify screenshots are generated
- Verify results files are created with correct content

### Property-Based Testing
- Generate random load patterns and verify auto-balancer always converges
- Generate random cluster configurations and verify setup always succeeds
- Generate random metric queries and verify results are consistent

### Manual Testing
- Run each demo scenario manually
- Verify Grafana dashboards display correctly
- Verify screenshots are readable and informative
- Verify documentation is clear and complete
- Verify results match expected patterns

### Performance Testing
- Measure time to convergence for each scenario
- Measure resource usage (CPU, memory, disk) during demos
- Verify demos complete within reasonable time (< 10 minutes each)

## Implementation Notes

### Grafana Screenshot Generation

Use Grafana's rendering API:

```bash
# Generate screenshot of a specific panel
curl -H "Authorization: Bearer ${GRAFANA_API_KEY}" \
  "http://localhost:3000/render/d-solo/${DASHBOARD_UID}/autobalancer-demo?orgId=1&panelId=${PANEL_ID}&width=1200&height=600&from=now-10m&to=now" \
  -o screenshot.png
```

For automated API key generation:

```bash
# Create API key via Grafana API
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"automation","role":"Admin"}' \
  http://admin:admin@localhost:3000/api/auth/keys
```

### Auto-Balancer Configuration Tuning

Based on AutoMQ source code analysis:

```properties
# Enable auto-balancer
autobalancer.controller.enable=true

# Configure goals for traffic balancing
autobalancer.controller.goals=kafka.autobalancer.goals.NetworkInUsageDistributionGoal,kafka.autobalancer.goals.NetworkOutUsageDistributionGoal

# Faster detection for demo purposes (default is 60000ms)
autobalancer.controller.anomaly.detect.interval.ms=30000

# Execution concurrency
autobalancer.controller.execution.concurrency=50

# Batch interval between partition moves
autobalancer.controller.execution.interval.ms=5000

# Metrics reporter on brokers
metric.reporters=kafka.autobalancer.metricsreporter.AutoBalancerMetricsReporter
```

### Waiting for Auto-Balancer Completion

Poll Prometheus metrics to detect when balancing is complete:

```bash
# Check if standard deviation has decreased below threshold
while true; do
  std_dev=$(curl -s "http://localhost:9090/api/v1/query?query=stddev(kafka_server_broker_topic_metrics_bytes_in_per_sec)" | jq '.data.result[0].value[1]')
  if (( $(echo "$std_dev < $THRESHOLD" | bc -l) )); then
    echo "Balancing complete"
    break
  fi
  sleep 10
done
```

### Directory Structure

```
auto-balancing-demos/
├── README.md
├── common/
│   ├── scripts/
│   │   ├── wait-for-container.sh
│   │   ├── query-prometheus.sh
│   │   ├── generate-grafana-screenshot.sh
│   │   └── format-metrics-table.sh
│   ├── grafana/
│   │   ├── dashboard-autobalancer.json
│   │   └── datasource-prometheus.yml
│   └── jmx-exporter-config.yml
├── traffic-based/
│   ├── docker-compose.yml
│   ├── README.md
│   ├── prometheus.yml
│   ├── scripts/
│   │   ├── setup.sh
│   │   ├── generate-load.sh
│   │   ├── collect-metrics.sh
│   │   ├── generate-screenshots.sh
│   │   ├── verify-balance.sh
│   │   └── cleanup.sh
│   ├── grafana/
│   │   └── dashboards/
│   └── results/
│       ├── before-balancing.md
│       ├── after-balancing.md
│       ├── metrics-comparison.md
│       └── screenshots/
├── qps-based/
│   └── (same structure)
├── slow-node-isolation/
│   └── (same structure)
├── scale-up/
│   └── (same structure)
└── scale-down/
    └── (same structure)
```
