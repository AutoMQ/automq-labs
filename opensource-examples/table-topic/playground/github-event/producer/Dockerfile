FROM python:3.9-slim

WORKDIR /app


COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY event_producer.py .
COPY github_event.avsc .

# Default environment variables
ENV KAFKA_BOOTSTRAP_SERVERS=automq:9092
ENV SCHEMA_REGISTRY_URL=http://schema-registry:8081
ENV TOPIC_NAME=github_events_iceberg
ENV EVENT_DATE=2025-01-01
ENV EVENT_HOUR=15

ENTRYPOINT ["python", "event_producer.py"]

