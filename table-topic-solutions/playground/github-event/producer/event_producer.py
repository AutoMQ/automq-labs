import json
import gzip
import shutil
import os
import sys
import time
import logging
import requests
import dateutil.parser
from datetime import datetime, timedelta, timezone
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# Configure logging
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').upper()
# Create a stream handler with unbuffered output
handler = logging.StreamHandler(sys.stdout)
handler.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)

# Configure root logger
root_logger = logging.getLogger()
root_logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))
root_logger.handlers = []  # Clear existing handlers
root_logger.addHandler(handler)

logger = logging.getLogger(__name__)

# ================= Configuration =================
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'automq:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://schema-registry:8081')
TOPIC_NAME = os.getenv('TOPIC_NAME', 'github_events_iceberg')
KAFKA_DEBUG = os.getenv('KAFKA_DEBUG', '')  # Set to 'all' or 'broker,topic,msg' for debug logs

# Read Avro Schema
schema_path = os.path.join(os.path.dirname(__file__), 'github_event.avsc')
with open(schema_path, 'r') as f:
    SCHEMA_STR = f.read()

class GithubEventMapper:
    """Maps complex GH JSON to flat Avro dictionary"""
    
    @staticmethod
    def to_timestamp(time_str):
        if not time_str: return None
        dt = dateutil.parser.parse(time_str)
        return int(dt.timestamp() * 1000)  # Convert to milliseconds

    @staticmethod
    def map_event(raw):
        payload = raw.get('payload', {})
        t = raw.get('type')

        # 1. Basic fields
        record = {
            "id": raw.get("id"),
            "type": t,
            "created_at": GithubEventMapper.to_timestamp(raw.get("created_at")),
            "actor_login": raw.get("actor", {}).get("login"),
            "repo_name": raw.get("repo", {}).get("name")
        }
            
        return record

def format_hour_key(dt):
    """Format datetime to GH Archive filename format: YYYY-MM-DD-HH"""
    return dt.strftime("%Y-%m-%d-%H")


def get_initial_start_hour():
    """Calculate initial start time: 3 days ago (UTC)"""
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=3)
    # Round down to hour
    return start.replace(minute=0, second=0, microsecond=0)


def get_target_hour():
    """Calculate target time: 3 hours ago (UTC)"""
    now = datetime.now(timezone.utc)
    target = now - timedelta(hours=3)
    # Round down to hour
    return target.replace(minute=0, second=0, microsecond=0)


def process_hour(date_str, hour, producer, avro_serializer):
    """Process data for a single hour"""
    start_time = time.time()
    delivery_success = 0
    delivery_failed = 0
    
    def delivery_report(err, msg):
        nonlocal delivery_success, delivery_failed
        if err:
            delivery_failed += 1
            logger.error(f"❌ Delivery failed: {err}")
        else:
            delivery_success += 1
            # Log detailed delivery info only at debug level
            if logger.level == logging.DEBUG:
                logger.debug(f"✅ Message delivered: topic={msg.topic()}, partition={msg.partition()}, offset={msg.offset()}")

    # Download & Process
    file_name = f"{date_str}-{hour}.json.gz"
    url = f"https://data.gharchive.org/{file_name}"
    logger.info(f"📥 Processing: {url}")

    try:
        # Stream download and decompress
        response = requests.get(url, stream=True, timeout=300)
        response.raise_for_status()
        
        with open(file_name, 'wb') as f:
            shutil.copyfileobj(response.raw, f)
        
        count = 0
        with gzip.open(file_name, 'rt', encoding='utf-8') as f:
            for line in f:
                if not line.strip(): 
                    continue
                
                try:
                    raw_json = json.loads(line)
                    # Core transformation
                    avro_record = GithubEventMapper.map_event(raw_json)
                    
                    # Send message, wait if queue is full
                    while True:
                        try:
                            producer.produce(
                                topic=TOPIC_NAME,
                                key=str(avro_record['id']),
                                value=avro_serializer(avro_record, SerializationContext(TOPIC_NAME, MessageField.VALUE)),
                                on_delivery=delivery_report
                            )
                            break  # Successfully sent, exit retry loop
                        except BufferError:
                            # Queue is full, process sent messages first, then retry
                            producer.poll(1)
                            continue

                    count += 1
                    # Call poll every 100 messages to ensure timely delivery
                    if count % 100 == 0:
                        producer.poll(0)
                    # Print progress every 2000 messages
                    if count % 2000 == 0:
                        logger.info(f"  ↳ Sent {count} events...")
                        
                except Exception as e:
                    logger.warning(f"  ⚠️ Error processing line: {e}")
                    continue
        
        # Flush remaining messages
        logger.debug("Flushing producer...")
        producer.flush(timeout=30)
        
        elapsed = time.time() - start_time
        rate = count / elapsed if elapsed > 0 else 0
        logger.info(f"✅ Completed: {count} events sent from {url} in {elapsed:.2f}s ({rate:.0f} events/sec)")
        logger.info(f"   Delivery stats: {delivery_success} successful, {delivery_failed} failed")
        return count

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            logger.warning(f"⚠️ Data not available yet: {url} (404)")
            return 0
        else:
            logger.error(f"❌ HTTP error processing {url}: {e}")
            raise
    except Exception as e:
        logger.error(f"❌ Error processing {url}: {e}", exc_info=True)
        raise
    finally:
        if os.path.exists(file_name):
            os.remove(file_name)


def run_continuous_producer():
    """Main loop for continuously running producer"""
    logger.info("=" * 60)
    logger.info("🚀 Starting Continuous GH Archive Producer")
    logger.info("=" * 60)
    
    # Setup Kafka (initialize outside loop to avoid repeated creation)
    logger.info("📡 Initializing Kafka producer...")
    logger.info(f"   Bootstrap servers: {KAFKA_BOOTSTRAP_SERVERS}")
    logger.info(f"   Topic: {TOPIC_NAME}")
    logger.info(f"   Schema Registry: {SCHEMA_REGISTRY_URL}")
    
    try:
        schema_registry_client = SchemaRegistryClient({'url': SCHEMA_REGISTRY_URL})
        logger.info("✅ Schema Registry client created")
        avro_serializer = AvroSerializer(schema_registry_client, SCHEMA_STR)
        logger.info("✅ Avro serializer created")
    except Exception as e:
        logger.error(f"❌ Failed to initialize Schema Registry: {e}", exc_info=True)
        raise
    
    # Configure Producer: increase queue size for higher throughput
    producer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'queue.buffering.max.messages': 100000,  # Increase queue size
        'queue.buffering.max.kbytes': 1048576,  # 1GB
        'batch.num.messages': 10000,  # Batch size
        'log.connection.close': True,  # Log connection close events
    }
    
    # Add debug configuration if specified
    if KAFKA_DEBUG:
        producer_config['debug'] = KAFKA_DEBUG
        logger.info(f"🔍 Kafka debug enabled: {KAFKA_DEBUG}")
    
    try:
        producer = Producer(producer_config)
        logger.info("✅ Kafka producer created")
        
        # Test connection
        logger.info("🔌 Testing Kafka connection...")
        metadata = producer.list_topics(timeout=10)
        logger.info(f"✅ Connected to Kafka. Available topics: {len(metadata.topics)}")
        if TOPIC_NAME in metadata.topics:
            topic_metadata = metadata.topics[TOPIC_NAME]
            logger.info(f"✅ Topic '{TOPIC_NAME}' exists with {len(topic_metadata.partitions)} partitions")
        else:
            logger.warning(f"⚠️  Topic '{TOPIC_NAME}' not found! It may be created automatically.")
    except Exception as e:
        logger.error(f"❌ Failed to connect to Kafka: {e}", exc_info=True)
        raise
    
    # Use variable to track last processed hour (stateless operation)
    last_processed_hour = None
    
    # Determine start time
    if last_processed_hour is None:
        # First run, start from 3 days ago
        current_hour = get_initial_start_hour()
        logger.info(f"🆕 Starting from {format_hour_key(current_hour)} (3 days ago)")
    else:
        # Resume from last processed time point
        current_hour = last_processed_hour + timedelta(hours=1)
        logger.info(f"🔄 Resuming from {format_hour_key(current_hour)}")
    
    cycle_count = 0
    while True:
        cycle_count += 1
        logger.info("")
        logger.info("=" * 60)
        logger.info(f"📊 Cycle #{cycle_count} - {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
        logger.info("=" * 60)
        
        target_hour = get_target_hour()
        logger.info(f"🎯 Target hour: {format_hour_key(target_hour)} (3 hours ago)")
        logger.info(f"📍 Current hour: {format_hour_key(current_hour)}")
        
        # Process all hours that need processing
        processed_in_cycle = 0
        while current_hour < target_hour:
            date_str = current_hour.strftime("%Y-%m-%d")
            hour_str = current_hour.strftime("%H")
            
            try:
                count = process_hour(date_str, hour_str, producer, avro_serializer)
                if count > 0:
                    processed_in_cycle += 1
                    # After successful processing, update variable and move to next hour
                    last_processed_hour = current_hour
                    current_hour += timedelta(hours=1)
                else:
                    # Data not available (possibly 404), wait before retrying
                    logger.info(f"⏳ Waiting 60 seconds before retrying...")
                    time.sleep(60)
                    # Don't update current_hour, will retry in next cycle
                    break
                    
            except Exception as e:
                logger.error(f"❌ Failed to process {format_hour_key(current_hour)}: {e}", exc_info=True)
                logger.info(f"⏳ Waiting 60 seconds before retrying...")
                time.sleep(60)
                # Don't update current_hour, will retry in next cycle
                break
        
        if processed_in_cycle > 0:
            logger.info("")
            logger.info(f"✅ Cycle completed: Processed {processed_in_cycle} hours")
        else:
            logger.info("")
            logger.info(f"⏸️  No new data to process (caught up to {format_hour_key(target_hour)})")
        
        # Wait before next check (target time advances with current time)
        wait_seconds = 300  # 5 minutes
        logger.info(f"⏳ Waiting {wait_seconds} seconds before next cycle...")
        time.sleep(wait_seconds)

if __name__ == "__main__":
    # Continuous mode: start from 3 days ago, continuously pull up to 3 hours ago
    try:
        run_continuous_producer()
    except KeyboardInterrupt:
        logger.info("\n\n⚠️  Producer stopped by user")
    except Exception as e:
        logger.error(f"\n\n❌ Fatal error: {e}", exc_info=True)
        raise