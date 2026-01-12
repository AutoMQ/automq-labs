#!/usr/bin/env python3

import argparse
import random
import time
from typing import Tuple
from kafka import KafkaProducer
from user_pb2 import UserData, UserRole
from product_pb2 import ProductData, ProductCategory, ProductStatus, DataValue, Item, Metadata
from common_pb2 import Address, ContactInfo, TimeRange
from event_pb2 import Event, Entity
from examples.clients.core import common_structs_pb2
from examples.clients.platform import stream_info_pb2
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

        # Populate new complex fields
        # 1. complex_attributes (map<string, DataValue>)
        # String value
        slogan_val = DataValue()
        slogan_val.string_value = fake.bs()
        product.complex_attributes["marketing_slogan"].CopyFrom(slogan_val)

        # Int value
        score_val = DataValue()
        score_val.int_value = random.randint(100, 999)
        product.complex_attributes["internal_score"].CopyFrom(score_val)

        # String Array
        colors_val = DataValue()
        colors_val.string_array.values.extend([fake.color_name() for _ in range(3)])
        product.complex_attributes["available_colors"].CopyFrom(colors_val)

        # 2. items (repeated Item)
        for _ in range(random.randint(1, 3)):
            item = product.items.add()
            item.name = fake.file_name()
            item.data = fake.binary(length=16)

        # 3. extra_metadata (Metadata)
        product.extra_metadata.sequence_number = random.randint(1, 100000)
        product.extra_metadata.is_active = random.choice([True, False])

        # 4. metadata_bytes
        product.metadata_bytes = fake.binary(length=32)

        # 5. timestamp_uint64
        product.timestamp_uint64 = int(time.time() * 1000)

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

    def send_event_message(self, topic: str):
        fake = Faker()
        event = Event()
        
        # Basic event fields
        event.event_id = fake.uuid4()
        event.event_name = random.choice(["page_view", "button_click", "form_submit", "purchase", "login"])
        event.event_time = int(time.time() * 1000)  # milliseconds
        
        # Add entities
        for _ in range(random.randint(1, 3)):
            entity = Entity()
            entity.entity = random.choice(["user", "product", "page", "session"])
            entity.version = f"v{random.randint(1, 3)}"
            entity.alias = fake.word()
            entity.data = fake.binary(length=random.randint(16, 64))
            event.entities.append(entity)
        
        # Add system_params_map
        # String value
        str_val = common_structs_pb2.DataValue()
        str_val.string_value = fake.user_agent()
        event.system_params_map["user_agent"].CopyFrom(str_val)
        
        # Int value
        int_val = common_structs_pb2.DataValue()
        int_val.int_value = random.randint(200, 500)
        event.system_params_map["response_time_ms"].CopyFrom(int_val)
        
        # Bool value
        bool_val = common_structs_pb2.DataValue()
        bool_val.bool_value = random.choice([True, False])
        event.system_params_map["is_mobile"].CopyFrom(bool_val)
        
        # Add user_params_map
        # String value
        user_str = common_structs_pb2.DataValue()
        user_str.string_value = fake.url()
        event.user_params_map["referrer"].CopyFrom(user_str)
        
        # Float value
        float_val = common_structs_pb2.DataValue()
        float_val.float_value = round(random.uniform(0, 100), 2)
        event.user_params_map["scroll_percentage"].CopyFrom(float_val)
        
        # String array
        tags_val = common_structs_pb2.DataValue()
        string_arr = common_structs_pb2.StringArray()
        string_arr.values.extend([fake.word() for _ in range(3)])
        tags_val.string_array.CopyFrom(string_arr)
        event.user_params_map["tags"].CopyFrom(tags_val)
        
        # Add stream_metadata
        stream_meta = stream_info_pb2.StreamInfo()
        stream_meta.streamPartitionID = random.randint(0, 99)
        stream_meta.streamTime = int(time.time() * 1000)
        event.stream_metadata.CopyFrom(stream_meta)
        
        future = self.producer.send(topic, value=event)
        result = future.get(timeout=10)
        print(f"Event message sent to {topic}: {result}")
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
    p = argparse.ArgumentParser(description="Protobuf raw producer for product/user/event messages")
    p.add_argument("pos_topic", nargs="?", help="Kafka topic (positional)")
    p.add_argument("pos_type", nargs="?", choices=["product", "user", "event"], help="Message type (positional)")
    p.add_argument("--topic", dest="opt_topic", help="Kafka topic (flag)")
    p.add_argument("--type", dest="opt_type", choices=["product", "user", "event"], help="Message type (flag)")
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
        elif msg_type == "user":
            producer.send_user_message(topic=topic)
        else:  # event
            producer.send_event_message(topic=topic)
    finally:
        producer.close()


if __name__ == '__main__':
    main()
