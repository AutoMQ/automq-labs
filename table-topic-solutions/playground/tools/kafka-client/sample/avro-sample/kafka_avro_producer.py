#!/usr/bin/env python3

import json
import io
import random
from kafka import KafkaProducer
from avro import schema, io as avro_io
from faker import Faker

class AvroKafkaProducer:
    def __init__(self, bootstrap_servers='automq:9092', schema_file='schema/Order.avsc'):
        with open(schema_file, 'r') as f:
            schema_json = json.load(f)
        
        self.schema = schema.parse(json.dumps(schema_json))
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=self._avro_serializer
        )
    
    def _avro_serializer(self, data):
        writer = avro_io.DatumWriter(self.schema)
        bytes_writer = io.BytesIO()
        encoder = avro_io.BinaryEncoder(bytes_writer)
        writer.write(data, encoder)
        return bytes_writer.getvalue()
    
    def send_order_message(self, topic, order_id, product_name, order_description):
        order_data = {
            'order_id': order_id,
            'product_name': product_name,
            'order_description': order_description
        }
        
        future = self.producer.send(topic, value=order_data)
        result = future.get(timeout=10)
        print(f"Order message sent to {topic}: {result}")
        return result
    
    def close(self):
        self.producer.close()

def main():
    producer = AvroKafkaProducer()
    fake = Faker()
    
    try:
        # Send order message example with random data
        random_order_id = random.randint(100000000000000, 999999999999999) # Example range for long
        random_product_name = fake.word()
        random_order_description = fake.sentence()

        producer.send_order_message(
            topic='Order',
            order_id=random_order_id,
            product_name=random_product_name,
            order_description=random_order_description
        )
    finally:
        producer.close()

if __name__ == '__main__':
    main()