#!/usr/bin/env python3

import argparse
import random
import time
from typing import Tuple
from kafka import KafkaProducer
from user_pb2 import UserData, UserRole
from product_pb2 import ProductData, ProductCategory, ProductStatus
from common_pb2 import Address, ContactInfo, TimeRange
from faker import Faker
from google.protobuf.timestamp_pb2 import Timestamp


class ProtobufKafkaProducer:
    def __init__(self, bootstrap_servers='automq:9092'):
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda x: x.SerializeToString(),
        )

    def send_product_message(self, topic: str):
        fake = Faker()
        product = ProductData()
        
        product.product_id = fake.uuid4()
        product.name = fake.catch_phrase()
        product.price = round(random.uniform(10.0, 10000.0), 2)
        product.discount_rate = round(random.uniform(0.0, 0.5), 2)
        product.is_available = random.choice([True, False])

        product.stock_quantity = random.randint(0, 1000)
        product.view_count = random.randint(0, 1_000_000)
        product.sku_hash = random.randint(0, 2**32 - 1)

        product.product_image = fake.binary(length=64)
        product.status = random.choice([ProductStatus.ACTIVE, ProductStatus.INACTIVE, ProductStatus.OUT_OF_STOCK])

        product.category.name = fake.word()
        product.category.level = random.randint(1, 5)
        product.tags.extend([fake.word() for _ in range(random.randint(1, 4))])
        for _ in range(random.randint(0, 2)):
            sub_cat = ProductCategory()
            sub_cat.name = fake.word()
            sub_cat.level = random.randint(1, 3)
            product.sub_categories.append(sub_cat)

        now = Timestamp()
        now.GetCurrentTime()
        product.created_at.CopyFrom(now)
        product.updated_at.CopyFrom(now)

        if random.choice([True, False]):
            product.manufacturer = fake.company()

        if random.choice([True, False]):
            product.seller_name = fake.name()
        else:
            product.seller_id = random.randint(1, 10_000)

        product.warehouse_address.street = fake.street_address()
        product.warehouse_address.city = fake.city()
        product.warehouse_address.postal_code = random.randint(10000, 99999)
        if random.choice([True, False]):
            product.warehouse_address.country = fake.country()
        if random.choice([True, False]):
            product.warehouse_address.state = fake.state()

        product.supplier_contact.email = fake.company_email()
        if random.choice([True, False]):
            product.supplier_contact.phone = fake.phone_number()
        if random.choice([True, False]):
            product.supplier_contact.website = fake.url()

        for _ in range(random.randint(0, 2)):
            addr = Address()
            addr.street = fake.street_address()
            addr.city = fake.city()
            addr.postal_code = random.randint(10000, 99999)
            product.shipping_origins.append(addr)

        product.attributes["color"] = fake.safe_color_name()
        product.attributes["material"] = random.choice(["cotton", "leather", "steel", "plastic"])
        product.attributes["region"] = fake.country_code()

        for month in range(1, random.randint(2, 4)):
            product.price_history[f"2025-{month:02d}"] = random.randint(1000, 200000)

        base_ts = int(time.time())
        promo_window = TimeRange()
        promo_window.start_timestamp = base_ts
        promo_window.end_timestamp = base_ts + 2 * 86400
        product.availability_windows["PROMO"].CopyFrom(promo_window)

        weekday = product.availability_windows["WEEKDAY"]
        weekday.start_timestamp = base_ts + 86400
        weekday.end_timestamp = weekday.start_timestamp + 3600
        weekend = product.availability_windows["WEEKEND"]
        weekend.start_timestamp = base_ts + 2 * 86400
        weekend.end_timestamp = weekend.start_timestamp + 7200

        future = self.producer.send(topic, value=product)
        result = future.get(timeout=10)
        print(f"Product message sent to {topic}: {result}")
        return result

    def send_user_message(self, topic: str):
        fake = Faker()
        user = UserData()
        
        user.user_id = fake.uuid4()
        user.username = fake.user_name()
        user.email = fake.email()
        user.account_balance = round(random.uniform(0.0, 10000.0), 2)
        user.credit_score = round(random.uniform(300.0, 850.0), 1)
        user.is_verified = random.choice([True, False])

        user.total_orders = random.randint(0, 500)
        user.loyalty_points = random.randint(-100, 5000)
        user.profile_views = random.randint(0, 1_000_000)

        user.profile_picture = fake.binary(length=40)
        user.role = random.choice([UserRole.CUSTOMER, UserRole.SELLER, UserRole.ADMIN])

        user.address.street = fake.street_address()
        user.address.city = fake.city()
        user.address.postal_code = random.randint(10000, 99999)

        user.interests.extend([fake.word() for _ in range(random.randint(1, 4))])
        user.favorite_product_ids.extend([random.randint(1, 1000) for _ in range(random.randint(0, 3))])

        now = Timestamp()
        now.GetCurrentTime()
        user.registered_at.seconds = int(time.time()) - random.randint(0, 365 * 24 * 3600)
        user.last_login_at.CopyFrom(now)

        if random.choice([True, False]):
            user.referral_code = fake.bothify(text='????-####')

        if random.choice([True, False]):
            user.contact_email = fake.email()
        else:
            user.contact_phone = random.randint(1000000000, 9999999999)

        for _ in range(random.randint(0, 2)):
            addr = Address()
            addr.street = fake.street_address()
            addr.city = fake.city()
            addr.postal_code = random.randint(10000, 99999)
            user.shipping_addresses.append(addr)

        user.preferences["theme"] = random.choice(["light", "dark"])
        user.preferences["language"] = fake.language_code()

        for days in range(3):
            key = f"2025-11-{days+1:02d}"
            user.login_counts[key] = random.randint(0, 10)

        email_contact = ContactInfo()
        email_contact.email = fake.email()
        user.contacts_by_channel["EMAIL"].CopyFrom(email_contact)

        sms_contact = ContactInfo()
        sms_contact.phone = fake.phone_number()
        user.contacts_by_channel["SMS"].CopyFrom(sms_contact)

        for _ in range(random.randint(0, 2)):
            trusted = user.trusted_contacts.add()
            trusted.email = fake.email()
            if random.choice([True, False]):
                trusted.phone = fake.phone_number()

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

    try:
        if msg_type == "product":
            producer.send_product_message(topic=topic)
        else:
            producer.send_user_message(topic=topic)
    finally:
        producer.close()


if __name__ == '__main__':
    main()
