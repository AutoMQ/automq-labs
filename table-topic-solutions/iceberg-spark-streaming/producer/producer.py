import argparse
import json
import time
import random
import os
from faker import Faker
from confluent_kafka import Producer
from confluent_kafka.admin import AdminClient, NewTopic
from confluent_kafka.cimpl import KafkaException, KafkaError

# Configuration
BOOTSTRAP_SERVERS = os.environ.get('KAFKA_BOOTSTRAP_SERVERS', 'automq:9092')
TOPIC_NAME = 'telemetry'

# Initialize Faker
fake = Faker()

def create_topic(topic_name, bootstrap_servers):
    """Creates a Kafka topic with AutoMQ-specific table properties."""
    admin_client = AdminClient({'bootstrap.servers': bootstrap_servers})
    
    # These properties enable the topic to be backed by an Iceberg table
    topic_config = {
        'automq.table.topic.enable': 'true',
        'automq.table.topic.commit.interval.ms': '2000',
        'automq.table.topic.schema.type': 'schemaless',
        'automq.table.topic.namespace': 'default',
        # Partition by hour based on the event timestamp
        'automq.table.topic.partition.by': '[hour(timestamp)]'
    }

    new_topic = NewTopic(
        topic_name,
        num_partitions=1,
        replication_factor=1,
        config=topic_config
    )

    futures = admin_client.create_topics([new_topic])
    
    for topic, future in futures.items():
        try:
            future.result(timeout=30)
            print(f"Topic '{topic}' created successfully with the following configuration:")
            for key, value in topic_config.items():
                print(f"  {key}: {value}")
        except KafkaException as e:
            error = e.args[0]
            if error.code() == KafkaError.TOPIC_ALREADY_EXISTS:
                print(f"Topic '{topic}' already exists. Skipping creation.")
            else:
                print(f"Failed to create topic '{topic}': {error.str()}")
                raise

def delivery_report(err, msg):
    """Callback for message delivery reports."""
    if err is not None:
        print(f"Message delivery failed: {err}")
    else:
        print(f"Message delivered to {msg.topic()} [partition {msg.partition()}] at offset {msg.offset()}")

def write_messages(topic_name, bootstrap_servers):
    """Generates and sends car data to the specified Kafka topic."""
    producer_conf = {'bootstrap.servers': bootstrap_servers}
    producer = Producer(producer_conf)

    print(f"Starting to send data to Kafka topic: {topic_name}")
    try:
        while True:
            vin = fake.vin()
            car_data = {
                "iccid": fake.credit_card_number(),
                "speed": round(random.uniform(0, 220), 2),
                "request": random.randint(1000, 5000),
                "response": random.randint(1000, 5000)
            }
            
            producer.produce(
                topic=topic_name,
                key=vin.encode('utf-8'),
                value=json.dumps(car_data).encode('utf-8'),
                on_delivery=delivery_report
            )
            
            # producer.poll() is used to serve delivery reports (and other callbacks)
            # A zero timeout ensures it's non-blocking
            producer.poll(0)
            
            print(f"Sent message: key={vin}")
            time.sleep(1) # Wait for 1 second

    except KeyboardInterrupt:
        print("Stopping producer...")
    finally:
        # Wait for any outstanding messages to be delivered and delivery reports to be received.
        producer.flush()
        print("Producer flushed and closed.")

def main():
    """Main CLI entrypoint."""
    parser = argparse.ArgumentParser(description="Kafka Producer CLI for Car Data")
    parser.add_argument(
        '--bootstrap-servers',
        default=BOOTSTRAP_SERVERS,
        help=f"Kafka bootstrap servers (default: {BOOTSTRAP_SERVERS})"
    )
    
    subparsers = parser.add_subparsers(dest='command', required=True)

    # Sub-parser for creating a topic
    create_parser = subparsers.add_parser('create-topic', help='Create the Kafka topic.')
    create_parser.add_argument(
        '--topic',
        default=TOPIC_NAME,
        help=f"Topic name to create (default: {TOPIC_NAME})"
    )

    # Sub-parser for writing messages
    write_parser = subparsers.add_parser('write-messages', help='Start writing messages to the topic.')
    write_parser.add_argument(
        '--topic',
        default=TOPIC_NAME,
        help=f"Topic name to write to (default: {TOPIC_NAME})"
    )

    args = parser.parse_args()

    if args.command == 'create-topic':
        create_topic(args.topic, args.bootstrap_servers)
    elif args.command == 'write-messages':
        write_messages(args.topic, args.bootstrap_servers)

if __name__ == "__main__":
    main()