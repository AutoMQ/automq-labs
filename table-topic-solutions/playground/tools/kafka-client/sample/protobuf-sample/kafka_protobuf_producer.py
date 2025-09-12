#!/usr/bin/env python3

import argparse
import random
from typing import Tuple
from kafka import KafkaProducer
from user_pb2 import UserData
from product_pb2 import ProductData
from faker import Faker


class ProtobufKafkaProducer:
    def __init__(self, bootstrap_servers='automq:9092'):
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda x: x.SerializeToString(),
        )

    def send_product_message(self, topic: str, product_id: str, name: str, description: str, price: float,
                              seller_user_id: str, seller_name: str, seller_email: str):
        seller = UserData()
        seller.user_id = seller_user_id
        seller.name = seller_name
        seller.email = seller_email

        product = ProductData()
        product.product_id = product_id
        product.name = name
        product.description = description
        product.price = price
        product.seller.CopyFrom(seller)

        future = self.producer.send(topic, value=product)
        result = future.get(timeout=10)
        print(f"Product message sent to {topic}: {result}")
        return result

    def send_user_message(self, topic: str, user_id: str, name: str, email: str):
        user = UserData()
        user.user_id = user_id
        user.name = name
        user.email = email

        future = self.producer.send(topic, value=user)
        result = future.get(timeout=10)
        print(f"User message sent to {topic}: {result}")
        return result

    def close(self):
        self.producer.close()


def parse_args() -> Tuple[str, str]:
    """Return (topic, msg_type). Supports both flags and positional args.

    Priority:
    1) If --topic/--type provided, use them.
    2) Else if two positionals given, interpret as <topic> <type>.
    3) Else defaults: topic=product, type=product.
    """
    p = argparse.ArgumentParser(description="Protobuf raw producer for product/user messages")
    p.add_argument("pos_topic", nargs="?", help="Kafka topic (positional)")
    p.add_argument("pos_type", nargs="?", choices=["product", "user"], help="Message type (positional)")
    p.add_argument("--topic", dest="opt_topic", help="Kafka topic (flag)")
    p.add_argument("--type", dest="opt_type", choices=["product", "user"], help="Message type (flag)")
    ns = p.parse_args()

    topic = ns.opt_topic or ns.pos_topic or "product"
    msg_type = ns.opt_type or ns.pos_type or "product"
    return topic, msg_type


def main():
    topic, msg_type = parse_args()
    producer = ProtobufKafkaProducer()
    fake = Faker()

    try:
        if msg_type == "product":
            random_product_id = fake.uuid4()
            random_name = fake.word()
            random_description = fake.sentence()
            random_price = round(random.uniform(10.0, 10000.0), 2)
            random_seller_user_id = fake.uuid4()
            random_seller_name = fake.name()
            random_seller_email = fake.email()

            producer.send_product_message(
                topic=topic,
                product_id=random_product_id,
                name=random_name,
                description=random_description,
                price=random_price,
                seller_user_id=random_seller_user_id,
                seller_name=random_seller_name,
                seller_email=random_seller_email,
            )
        else:
            random_user_id = fake.uuid4()
            random_name = fake.name()
            random_email = fake.email()

            producer.send_user_message(
                topic=topic,
                user_id=random_user_id,
                name=random_name,
                email=random_email,
            )
    finally:
        producer.close()


if __name__ == '__main__':
    main()
