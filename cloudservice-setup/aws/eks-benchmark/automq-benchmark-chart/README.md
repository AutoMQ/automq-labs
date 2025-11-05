# AutoMQ Benchmark Helm Chart

This Helm chart deploys an AutoMQ benchmark job on a Kubernetes cluster.

## Prerequisites

- Kubernetes 1.16+
- Helm 3.0+
- An AutoMQ cluster running in the same Kubernetes cluster

## Installing the Chart

To install the chart with the release name `automq-benchmark`:

```bash
helm install automq-benchmark ./automq-benchmark-chart
```

To install with custom values:

```bash
helm install automq-benchmark ./automq-benchmark-chart -f custom-values.yaml
```

**Note:** If you need to re-run the benchmark task, first uninstall the existing deployment using `helm uninstall automq-benchmark`, then reinstall the chart.

## Uninstalling the Chart

To uninstall/delete the `automq-benchmark` deployment:

```bash
helm uninstall automq-benchmark
```

## Configuration

The following table lists the configurable parameters of the AutoMQ benchmark chart and their default values.

| Parameter                      | Description                                    | Default                                              |
|--------------------------------|------------------------------------------------|------------------------------------------------------|
| `job.name`                     | Name of the benchmark job                      | `automq-benchmark`                                   |
| `job.completions`              | Number of successful completions               | `1`                                                  |
| `job.parallelism`              | Number of parallel pods                        | `1`                                                  |
| `job.backoffLimit`             | Number of retries before marking job as failed | `3`                                                  |
| `job.restartPolicy`            | Restart policy for the job                     | `Never`                                              |
| `image.repository`             | AutoMQ image repository                        | `automqinc/automq`                                   |
| `image.tag`                    | AutoMQ image tag                               | `latest`                                             |
| `image.pullPolicy`             | Image pull policy                              | `IfNotPresent`                                       |
| `automq.username`              | AutoMQ username                                | `user1`                                              |
| `automq.password`              | AutoMQ password                                | `MrCrSQTVoB`                                         |
| `automq.bootstrapServer`       | AutoMQ bootstrap server                        | `automq-release-kafka.automq.svc.cluster.local:9092` |
| `automq.securityProtocol`      | Security protocol                              | `SASL_PLAINTEXT`                                     |
| `automq.saslMechanism`         | SASL mechanism                                 | `PLAIN`                                              |
| `benchmark.kafkaHeapOpts`      | Kafka heap options                             | `-Xmx1g -Xms1g`                                      |
| `benchmark.producerConfigs`    | Producer configurations                        | `batch.size=0`                                       |
| `benchmark.consumerConfigs`    | Consumer configurations                        | `fetch.max.wait.ms=1000`                             |
| `benchmark.topics`             | Number of topics                               | `10`                                                 |
| `benchmark.partitionsPerTopic` | Partitions per topic                           | `128`                                                |
| `benchmark.producersPerTopic`  | Producers per topic                            | `1`                                                  |
| `benchmark.groupsPerTopic`     | Consumer groups per topic                      | `1`                                                  |
| `benchmark.consumersPerGroup`  | Consumers per group                            | `1`                                                  |
| `benchmark.recordSize`         | Record size in bytes                           | `52224`                                              |
| `benchmark.sendRate`           | Send rate (messages/sec)                       | `160`                                                |
| `benchmark.warmupDuration`     | Warmup duration in minutes                     | `3`                                                  |
| `benchmark.testDuration`       | Test duration in minutes                       | `3`                                                  |
| `resources.requests.cpu`       | CPU request                                    | `500m`                                               |
| `resources.requests.memory`    | Memory request                                 | `2Gi`                                                |
| `resources.limits.cpu`         | CPU limit                                      | `2`                                                  |
| `resources.limits.memory`      | Memory limit                                   | `4Gi`                                                |

## Example Custom Values

```yaml
# custom-values.yaml
benchmark:
  topics: 20
  partitionsPerTopic: 256
  recordSize: 1024
  sendRate: 1000
  testDuration: 10

resources:
  requests:
    cpu: "1"
    memory: "4Gi"
  limits:
    cpu: "4"
    memory: "8Gi"

automq:
  bootstrapServer: "my-automq-cluster:9092"
```

## Monitoring

After the job completes, you can check the results by viewing the job logs:

```bash
kubectl logs job/automq-benchmark
```

To check the job status:

```bash
kubectl get jobs
kubectl describe job automq-benchmark
```

## Troubleshooting

1. **Job fails to start**: Check if the AutoMQ cluster is accessible and credentials are correct.
2. **Pod crashes**: Check resource limits and AutoMQ cluster capacity.
3. **Authentication errors**: Verify username, password, and security settings.

For more information, check the pod logs:

```bash
kubectl logs -l app=automq-benchmark
```