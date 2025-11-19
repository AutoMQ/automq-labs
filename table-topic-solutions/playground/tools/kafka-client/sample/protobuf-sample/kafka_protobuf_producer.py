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
        
        # Basic product information
        product.product_id = fake.uuid4()
        product.name = fake.catch_phrase()
        product.description = fake.sentence()
        product.price = round(random.uniform(10.0, 10000.0), 2)
        product.discount_rate = round(random.uniform(0.0, 0.5), 2)
        product.is_available = random.choice([True, False])
        
        # Inventory and sales
        product.stock_quantity = random.randint(0, 1000)
        product.reserved_quantity = random.randint(-50, 100)
        product.total_sold = random.randint(0, 10000)
        product.view_count = random.randint(0, 100000)
        product.rating_sum = random.randint(-100, 5000)
        product.total_revenue_cents = random.randint(0, 10000000)
        
        # Fixed-size numeric fields
        product.sku_hash = random.randint(0, 2**32-1)
        product.warehouse_zone = random.randint(-1000, 1000)
        product.barcode = random.randint(0, 2**64-1)
        product.internal_id = random.randint(-2**63, 2**63-1)
        
        # Binary and enum
        product.product_image = fake.binary(length=100)
        product.status = random.choice([ProductStatus.ACTIVE, ProductStatus.INACTIVE, ProductStatus.OUT_OF_STOCK])
        
        # Nested message
        product.category.name = fake.word()
        product.category.level = random.randint(1, 5)
        
        # Repeated fields
        product.tags.extend([fake.word() for _ in range(random.randint(1, 5))])
        product.related_product_ids.extend([random.randint(1, 1000) for _ in range(random.randint(0, 3))])
        
        # Timestamps
        now = Timestamp()
        now.GetCurrentTime()
        product.created_at.CopyFrom(now)
        product.updated_at.CopyFrom(now)
        
        # Optional field
        if random.choice([True, False]):
            product.manufacturer = fake.company()
        
        # Oneof field
        if random.choice([True, False]):
            product.seller_name = fake.name()
        else:
            product.seller_id = random.randint(1, 10000)
        
        # Repeated nested message
        for _ in range(random.randint(0, 3)):
            sub_cat = ProductCategory()
            sub_cat.name = fake.word()
            sub_cat.level = random.randint(1, 3)
            product.sub_categories.append(sub_cat)
        
        # Using shared Address type - cross-file reference example
        product.warehouse_address.street = fake.street_address()
        product.warehouse_address.city = fake.city()
        product.warehouse_address.postal_code = random.randint(10000, 99999)
        if random.choice([True, False]):
            product.warehouse_address.country = fake.country()
        if random.choice([True, False]):
            product.warehouse_address.state = fake.state()
        
        # Using shared ContactInfo type
        product.supplier_contact.email = fake.company_email()
        if random.choice([True, False]):
            product.supplier_contact.phone = fake.phone_number()
        if random.choice([True, False]):
            product.supplier_contact.website = fake.url()
        
        # Repeated Address
        for _ in range(random.randint(0, 2)):
            addr = Address()
            addr.street = fake.street_address()
            addr.city = fake.city()
            addr.postal_code = random.randint(10000, 99999)
            product.shipping_origins.append(addr)

        # Map fields
        product.attributes["color"] = fake.color_name()
        product.attributes["material"] = random.choice(["cotton", "leather", "steel", "plastic"])
        product.attributes["region"] = fake.country_code()

        for month in range(1, random.randint(2, 4)):
            product.price_history[f"2025-{month:02d}"] = random.randint(1000, 200000)

        base_ts = int(time.time())
        for label in ["WEEKDAY", "WEEKEND"]:
            window = product.availability_windows[label]
            start = base_ts + random.randint(0, 5) * 86400
            window.start_timestamp = start
            window.end_timestamp = start + random.randint(1, 3) * 86400

        promo_window = TimeRange()
        promo_window.start_timestamp = base_ts
        promo_window.end_timestamp = base_ts + 2 * 86400
        product.availability_windows["PROMO"].CopyFrom(promo_window)

        # Repeated shared message
        for _ in range(random.randint(1, 3)):
            contact = product.vendor_contacts.add()
            contact.email = fake.company_email()
            if random.choice([True, False]):
                contact.phone = fake.phone_number()
            if random.choice([True, False]):
                contact.website = fake.url()

        future = self.producer.send(topic, value=product)
        result = future.get(timeout=10)
        print(f"Product message sent to {topic}: {result}")
        return result

    def send_user_message(self, topic: str):
        fake = Faker()
        user = UserData()
        
        # Basic user information
        user.user_id = fake.uuid4()
        user.username = fake.user_name()
        user.email = fake.email()
        user.account_balance = round(random.uniform(0.0, 10000.0), 2)
        user.credit_score = round(random.uniform(300.0, 850.0), 1)
        user.is_verified = random.choice([True, False])
        
        # User metrics
        user.total_orders = random.randint(0, 500)
        user.loyalty_points = random.randint(-100, 5000)
        user.successful_transactions = random.randint(0, 1000)
        user.total_spent_cents = random.randint(0, 1000000)
        user.review_score_sum = random.randint(-50, 500)
        user.profile_views = random.randint(0, 100000)
        
        # Fixed-size fields
        user.user_hash = random.randint(0, 2**32-1)
        user.timezone_offset = random.randint(-720, 720)
        user.phone_number = random.randint(1000000000, 9999999999)
        user.internal_user_id = random.randint(-2**63, 2**63-1)
        
        # Binary and enum
        user.profile_picture = fake.binary(length=50)
        user.role = random.choice([UserRole.CUSTOMER, UserRole.SELLER, UserRole.ADMIN])
        
        # Nested message
        user.address.street = fake.street_address()
        user.address.city = fake.city()
        user.address.postal_code = random.randint(10000, 99999)
        
        # Repeated fields
        user.interests.extend([fake.word() for _ in range(random.randint(1, 5))])
        user.favorite_product_ids.extend([random.randint(1, 1000) for _ in range(random.randint(0, 5))])
        
        # Timestamps
        now = Timestamp()
        now.GetCurrentTime()
        user.registered_at.seconds = int(time.time()) - random.randint(0, 365*24*3600)
        user.last_login_at.CopyFrom(now)
        
        # Optional field
        if random.choice([True, False]):
            user.referral_code = fake.bothify(text='????-####')
        
        # Oneof field
        if random.choice([True, False]):
            user.contact_email = fake.email()
        else:
            user.contact_phone = random.randint(1000000000, 9999999999)
        
        # Repeated nested message
        for _ in range(random.randint(0, 2)):
            addr = Address()
            addr.street = fake.street_address()
            addr.city = fake.city()
            addr.postal_code = random.randint(10000, 99999)
            user.shipping_addresses.append(addr)

        # Map fields
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

        # Repeated shared message
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
