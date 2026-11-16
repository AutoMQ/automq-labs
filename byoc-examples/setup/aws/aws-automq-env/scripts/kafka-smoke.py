#!/usr/bin/env python3
"""Verify one unique marker through the private SASL_PLAINTEXT endpoint."""
import os
import sys
import time
import uuid


def main():
    try:
        from confluent_kafka import Consumer, Producer, TopicPartition
        bootstrap = os.environ["KAFKA_BOOTSTRAP_SERVERS"]
        password = os.environ["TF_VAR_kafka_password"]
    except (ImportError, KeyError):
        print("Set KAFKA_BOOTSTRAP_SERVERS and TF_VAR_kafka_password; install confluent-kafka.", file=sys.stderr)
        return 2
    marker = f"eks-smoke-{uuid.uuid4()}".encode()
    settings = {"bootstrap.servers": bootstrap, "security.protocol": "SASL_PLAINTEXT",
                "sasl.mechanism": "PLAIN", "sasl.username": "eks-smoke", "sasl.password": password,
                "socket.timeout.ms": 10000}
    # Credentials stay in process memory; never argv, config files or output.
    consumer = Consumer({**settings, "group.id": marker.decode(), "enable.auto.commit": False})
    producer = Producer({**settings, "enable.idempotence": True, "message.timeout.ms": 30000})
    try:
        _, start = consumer.get_watermark_offsets(TopicPartition("eks-smoke", 0), timeout=20)
        consumer.assign([TopicPartition("eks-smoke", 0, start)])
        delivery = []
        producer.produce("eks-smoke", key=marker, value=marker, on_delivery=lambda error, message: delivery.append(error))
        if producer.flush(35) or delivery != [None]:
            raise RuntimeError("Marker delivery failed.")
        deadline = time.monotonic() + 45
        matches = 0
        while time.monotonic() < deadline:
            message = consumer.poll(1)
            if message is None:
                if matches:
                    break
                continue
            if message.error():
                raise RuntimeError("Kafka returned a consumer error.")
            if message.key() == marker:
                if message.value() != marker:
                    raise RuntimeError("Marker content differs from the produced record.")
                matches += 1
        if matches != 1:
            raise RuntimeError("Expected exactly one matching marker record.")
        print(f"PASS: produced and consumed exactly one matching record ({marker.decode()}).")
        return 0
    except Exception:
        # Client exceptions can contain connection properties. Do not print them.
        print("Kafka smoke failed. Check private DNS/routing, SASL credentials and topic/group ACLs.", file=sys.stderr)
        return 1
    finally:
        consumer.close()

if __name__ == "__main__":
    sys.exit(main())
