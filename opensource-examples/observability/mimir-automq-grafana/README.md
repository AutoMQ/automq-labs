# Mimir + AutoMQ Ingest Storage Lab

This lab is the runnable companion for `site/play/mimir.html`. It runs a small
Mimir ingest-storage deployment where AutoMQ provides the Kafka-compatible
durable log, and MinIO stands in for S3.

## Architecture

```text
Prometheus remote_write
  -> Mimir distributor
  -> AutoMQ Kafka API
  -> Mimir ingesters in two zones
  -> Mimir querier / query-scheduler / query-frontend
  -> Grafana dashboard

MinIO buckets:
  automq-data   AutoMQ stream data and WAL objects
  automq-ops    AutoMQ metadata / ops objects
  mimir-blocks  Mimir TSDB blocks
```

The important point is the write acknowledgement boundary: Mimir distributors
return success after AutoMQ persists the records. Ingesters consume the topic
asynchronously, keep recent samples queryable, write their local TSDB/WAL, and
ship blocks to object storage.

## What To Look For

- Write path is decoupled from ingester availability.
- Two ingesters own partition `0` from different zones for read-path HA.
- An ingester restart catches up from its Kafka consumer-group offset.
- AutoMQ stores its log data in the `automq-data` MinIO bucket.
- Mimir writes compactable TSDB blocks to the `mimir-blocks` MinIO bucket.

This is a local demo, not a production topology. It uses one AutoMQ node, one
Mimir partition, and short TSDB timings so the object-storage flow is visible
within minutes.

## Prerequisites

- Docker with Docker Compose.
- `just` for running the demo commands.
- `curl` for verification commands.
- At least 8 GB of available memory is recommended for the full stack.

The compose file publishes these host ports:

```text
3000              Grafana
9000, 9001        MinIO API and console
9009              Mimir distributor
9010-9016         Mimir query and component endpoints
9091              Prometheus
9092, 9093        AutoMQ broker and controller listeners
19090             AutoMQ metrics
29092             AutoMQ Kafka API from the host
```

## Quick Start

```bash
just up
just verify
just failure-demo
just down
```

First image pulls can take a while. If Docker Hub times out, rerun `just up`.

## Verify The Data Path

After `just up`, run:

```bash
just verify
```

The verification checks that:

- AutoMQ is reachable through the Kafka API.
- The Mimir ingest-storage topic `mimir-ingest` exists.
- Mimir distributor and query-frontend are ready.
- Grafana and Prometheus are ready.
- Mimir accepts Prometheus API queries through the query-frontend.
- Grafana can query Mimir through the provisioned datasource.

Prometheus remote-writes scraped samples to Mimir through:

```text
http://mimir-distributor:8080/api/v1/push
```

Grafana uses the provisioned Mimir datasource:

```text
uid: mimir
url: http://mimir-query-frontend:8080/prometheus
```

To confirm that Grafana can query metrics from Mimir, run:

```bash
curl -fsS --get \
  "http://localhost:3000/api/datasources/proxy/uid/mimir/api/v1/query" \
  --data-urlencode "query=up"
```

The response should contain `status: success` and `up` series for the Mimir,
AutoMQ, and Prometheus targets. If the result is initially empty, wait for one
or two Prometheus scrape intervals and retry.

## Dashboard Guide

Open Grafana at http://localhost:3000/d/mimir-automq-lab and check these
panels:

| Panel | What it shows |
| --- | --- |
| Samples Remote-Written To Mimir | Prometheus samples being sent to Mimir with remote_write. |
| Kafka Write Latency and Ingester Replay Delay | Mimir ingest-storage write latency and the delay before ingesters receive records from AutoMQ. |
| Distributor Uses Kafka Ingest Storage | Whether the Mimir distributor has ingest storage enabled. |
| Bytes Written To AutoMQ | Bytes written by Mimir ingest storage into the Kafka-compatible topic. |
| Ingester Consumption From AutoMQ | Ingesters consuming records from AutoMQ, grouped by zone. |

The demo does not use mocked metrics. Prometheus scrapes real metrics from
AutoMQ, Mimir, and Prometheus itself, then remote-writes those samples into
Mimir. The `just query-traffic` command only creates extra read-path activity by
querying Mimir for a short period.

## Commands

| Command | Purpose |
| --- | --- |
| `just up` | Start MinIO, AutoMQ, Mimir, Prometheus, and Grafana. |
| `just verify` | Check Kafka, Mimir, Grafana, Prometheus, and the Grafana-to-Mimir datasource path. |
| `just query-traffic` | Generate extra query traffic while Prometheus remote-writes samples. |
| `just produce` | Backward-compatible alias for `just query-traffic`. |
| `just failure-demo` | Stop one ingester, keep writes flowing through AutoMQ, restart it, and show replay logs. |
| `just logs` | Follow container logs. |
| `just down` | Stop and remove the local environment and volumes. |

## Endpoints

| Service | URL |
| --- | --- |
| Grafana dashboard | http://localhost:3000/d/mimir-automq-lab |
| Mimir query-frontend | http://localhost:9010/prometheus |
| Mimir distributor | http://localhost:9009 |
| Prometheus | http://localhost:9091 |
| AutoMQ Kafka API | `automq:9092` inside Docker, `localhost:29092` from the host |
| AutoMQ metrics | http://localhost:19090/metrics |
| MinIO console | http://localhost:9001 (`admin` / `password`) |

## Demo Flow

1. Run `just up`.
2. Open Grafana and watch the `Mimir + AutoMQ Ingest Storage Lab` dashboard.
3. Open MinIO and inspect `automq-data` and `mimir-blocks`.
4. Run `just failure-demo`.
5. Watch the replay-delay and ingester-consumption panels while the stopped
   ingester starts again.

The failure demo stops one ingester for 45 seconds. During that window,
Prometheus continues remote-writing samples to the Mimir distributor. The
distributor acknowledges writes after AutoMQ persists the records, and the
restarted ingester catches up from its Kafka consumer-group offset.

## Troubleshooting

- If image pulls from Docker Hub time out, rerun `just up` after the registry is
  reachable, or pre-pull the listed images from a registry mirror and tag them
  with the names used in `docker-compose.yml`.
- If a host port is already in use, update the port mapping in
  `docker-compose.yml` before running `just up`.
- If the Grafana or Mimir query initially returns no `up` series, wait for one
  or two 5-second Prometheus scrape intervals and run `just verify` again.
- If a service is not ready, run `docker compose ps` and
  `docker compose logs <service>` from this directory.
- To reset the demo state, run `just down` and then `just up`.

## Files

```text
configs/
  mimir/mimir.yaml
  grafana/
  prometheus/prometheus.yml
scripts/
  verify.sh
  generate-metrics.sh
  failure-ingester.sh
docker-compose.yml
justfile
```
