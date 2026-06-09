import argparse
import os
import time
from typing import Dict

from confluent_kafka import SerializingProducer
from confluent_kafka.admin import AdminClient, NewTopic
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import StringSerializer


ORDER_SCHEMA = """
{
  "type": "record",
  "name": "OrderEvent",
  "namespace": "automq.examples",
  "fields": [
    {"name": "order_id", "type": "long"},
    {"name": "customer_id", "type": "string"},
    {"name": "item", "type": "string"},
    {"name": "quantity", "type": "int"},
    {"name": "price", "type": "double"},
    {"name": "event_time", "type": "long"}
  ]
}
"""


def bootstrap_servers() -> str:
    return os.getenv("BOOTSTRAP_SERVERS", "automq:9092")


def schema_registry_url() -> str:
    return os.getenv("SCHEMA_REGISTRY_URL", "http://schema-registry:8081")


def table_topic_namespace() -> str:
    return os.getenv("TABLE_TOPIC_NAMESPACE", "automq_it")


def create_topic(args: argparse.Namespace) -> None:
    admin = AdminClient({"bootstrap.servers": bootstrap_servers()})
    config = {
        "automq.table.topic.enable": "true",
        "automq.table.topic.commit.interval.ms": "1000",
        "automq.table.topic.convert.value.type": "by_schema_id",
        "automq.table.topic.transform.value.type": "flatten",
        "automq.table.topic.namespace": args.namespace,
        "retention.ms": "345600000",
    }
    topic = NewTopic(args.topic, num_partitions=args.partitions, replication_factor=1, config=config)
    futures = admin.create_topics([topic])
    try:
        futures[args.topic].result(timeout=30)
        print(f"CREATED_TOPIC={args.topic}")
    except Exception as exc:
        if "already exists" in str(exc).lower():
            print(f"TOPIC_ALREADY_EXISTS={args.topic}")
            return
        raise


def order_to_dict(order: Dict, _ctx) -> Dict:
    return order


def produce_avro(args: argparse.Namespace) -> None:
    registry = SchemaRegistryClient({"url": schema_registry_url()})
    avro_serializer = AvroSerializer(registry, ORDER_SCHEMA, order_to_dict)
    producer = SerializingProducer(
        {
            "bootstrap.servers": bootstrap_servers(),
            "key.serializer": StringSerializer("utf_8"),
            "value.serializer": avro_serializer,
            "acks": "all",
        }
    )

    delivered = 0

    def on_delivery(err, msg):
        nonlocal delivered
        if err is not None:
            raise RuntimeError(f"delivery failed: {err}")
        delivered += 1
        print(f"ACK partition={msg.partition()} offset={msg.offset()}")

    base_time = int(time.time() * 1000)
    for i in range(args.count):
        value = {
            "order_id": i,
            "customer_id": f"customer-{i % 3}",
            "item": f"item-{i % 5}",
            "quantity": i + 1,
            "price": float((i + 1) * 10),
            "event_time": base_time + i,
        }
        producer.produce(args.topic, key=f"order-{i}", value=value, on_delivery=on_delivery)
        producer.poll(0)

    producer.flush(30)
    print(f"PRODUCED_TOPIC={args.topic}")
    print(f"PRODUCED_COUNT={delivered}")


def main() -> None:
    parser = argparse.ArgumentParser(description="AutoMQ OSS TableBucket example producer")
    subcommands = parser.add_subparsers(dest="command", required=True)

    create = subcommands.add_parser("create-topic", help="Create a Table Topic")
    create.add_argument("--topic", required=True)
    create.add_argument("--namespace", default=table_topic_namespace())
    create.add_argument("--partitions", type=int, default=3)
    create.set_defaults(func=create_topic)

    produce = subcommands.add_parser("produce-avro", help="Produce Avro records")
    produce.add_argument("--topic", required=True)
    produce.add_argument("--count", type=int, default=10)
    produce.set_defaults(func=produce_avro)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
