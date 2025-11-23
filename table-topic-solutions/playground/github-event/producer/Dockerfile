FROM python:3.9-slim

WORKDIR /app

# 安装 librdkafka 依赖（confluent-kafka 需要）
# 实际上 python:3.9-slim 可能不需要额外安装 librdkafka-dev 如果使用 binary wheel，
# 但为了保险起见，通常不需要，因为 confluent-kafka binary wheel 自带了 librdkafka。
# 如果遇到问题再添加。

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY event_producer.py .
COPY github_event.avsc .

# 默认环境变量
ENV KAFKA_BOOTSTRAP_SERVERS=automq:9092
ENV SCHEMA_REGISTRY_URL=http://schema-registry:8081
ENV TOPIC_NAME=github_events_iceberg
ENV EVENT_DATE=2025-01-01
ENV EVENT_HOUR=15

ENTRYPOINT ["python", "event_producer.py"]

