# Deploy AutoMQ Locally with Docker Compose and MinIO

This guide provides instructions for deploying AutoMQ locally using Docker Compose. It offers two configurations for different testing needs:

**Three-Node Cluster**: A more realistic setup with three AutoMQ brokers, ideal for testing clustering features and client failover.

Both setups use **MinIO** as a self-hosted, S3-compatible object storage backend.

## Prerequisites

*   [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) installed on your machine.
*   Kafka command-line tools installed locally, or you can run them from within the Docker containers as shown below.

## Deployment

Choose one of the following options to start your local AutoMQ cluster.

### Deploy a Three-Node Cluster

This setup simulates a production-like environment with three brokers.

```shell
docker compose -f docker-compose-bitnami-cluster.yaml up -d
```

## Testing the Deployment

After starting the cluster, you can use standard Kafka tools to interact with it.

### Connecting to the Cluster

*    `server1:9092,server2:9092,server3:9092`

### Running Kafka Tools

The easiest way to run Kafka tools without a local installation is to execute them inside one of the running containers. We'll use `automq-server1` for our examples.

#### 1. Basic Produce & Consume Test

**Open a terminal and start a producer** to send messages to a topic named `my-topic`:

```shell
docker exec -it automq-server1 bash -c "                                       \
  /opt/bitnami/kafka/bin/kafka-console-producer.sh                            \
    --broker-list server1:9092                                              \
    --topic my-topic"
```

Type some messages and press `Ctrl+C` when you are finished.

**Open a second terminal and start a consumer** to receive the messages:

```shell
docker exec -it automq-server1 bash -c "                                       \
  /opt/bitnami/kafka/bin/kafka-console-consumer.sh                            \
    --bootstrap-server server1:9092                                              \
    --topic my-topic                                                        \
    --from-beginning"
```

You should see the messages you sent earlier. Press `Ctrl+C` to exit.

#### 2. Simple Performance Test

You can run a small-scale performance test using `kafka-producer-perf-test.sh`. This example sends 1,024,000 messages of 1KB each to the `test-topic`.

**For a three-node cluster**, use all bootstrap servers for the test:

```shell
docker exec -it automq-server1 bash -c "                                       \
  /opt/bitnami/kafka/bin/kafka-producer-perf-test.sh --topic test-topic --num-records=1024000 --throughput 5120 --record-size 1024 --producer-props bootstrap.servers=server1:9092,server2:9092,server3:9092 linger.ms=100 batch.size=524288 buffer.memory=134217728 max.request.size=67108864"
```

#### A Note on Performance Tuning

> AutoMQ's architecture is built on object storage like S3. While this provides significant benefits in cost and scalability, it can introduce higher latency compared to traditional disk-based brokers.
>
> To achieve high throughput, it is crucial to optimize client-side configurations (e.g., `linger.ms`, `batch.size`). For detailed guidance, please refer to our official documentation:
>
> *   **[Performance Tuning for Clients](https://www.automq.com/docs/automq/configuration/performance-tuning-for-client)**

## Shutdown and Cleanup

To stop the containers and remove the network, run the `down` command corresponding to your deployment file.

```shell
docker compose -f docker-compose-bitnami-cluster.yaml down
```