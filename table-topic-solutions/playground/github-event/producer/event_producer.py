import json
import gzip
import shutil
import os
import time
import requests
import dateutil.parser
from datetime import datetime, timedelta, timezone
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# ================= Configuration =================
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'automq:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://schema-registry:8081')
TOPIC_NAME = os.getenv('TOPIC_NAME', 'github_events_iceberg')

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
    def delivery_report(err, msg):
        if err: 
            print(f"Delivery failed: {err}")

    # Download & Process
    file_name = f"{date_str}-{hour}.json.gz"
    url = f"https://data.gharchive.org/{file_name}"
    print(f"📥 Processing: {url}")

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
                        print(f"  ↳ Sent {count} events...")
                        
                except Exception as e:
                    print(f"  ⚠️ Error processing line: {e}")
                    continue
        
        producer.flush()
        print(f"✅ Completed: {count} events sent from {url}")
        return count

    except requests.exceptions.HTTPError as e:
        if e.response.status_code == 404:
            print(f"⚠️ Data not available yet: {url} (404)")
            return 0
        else:
            raise
    except Exception as e:
        print(f"❌ Error processing {url}: {e}")
        raise
    finally:
        if os.path.exists(file_name):
            os.remove(file_name)


def run_continuous_producer():
    """Main loop for continuously running producer"""
    print("=" * 60)
    print("🚀 Starting Continuous GH Archive Producer")
    print("=" * 60)
    
    # Setup Kafka (initialize outside loop to avoid repeated creation)
    print("📡 Initializing Kafka producer...")
    schema_registry_client = SchemaRegistryClient({'url': SCHEMA_REGISTRY_URL})
    avro_serializer = AvroSerializer(schema_registry_client, SCHEMA_STR)
    # Configure Producer: increase queue size for higher throughput
    producer_config = {
        'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS,
        'queue.buffering.max.messages': 100000,  # Increase queue size
        'queue.buffering.max.kbytes': 1048576,  # 1GB
        'batch.num.messages': 10000,  # Batch size
    }
    producer = Producer(producer_config)
    print("✅ Kafka producer initialized")
    
    # Use variable to track last processed hour (stateless operation)
    last_processed_hour = None
    
    # Determine start time
    if last_processed_hour is None:
        # First run, start from 3 days ago
        current_hour = get_initial_start_hour()
        print(f"🆕 Starting from {format_hour_key(current_hour)} (3 days ago)")
    else:
        # Resume from last processed time point
        current_hour = last_processed_hour + timedelta(hours=1)
        print(f"🔄 Resuming from {format_hour_key(current_hour)}")
    
    cycle_count = 0
    while True:
        cycle_count += 1
        print(f"\n{'='*60}")
        print(f"📊 Cycle #{cycle_count} - {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
        print(f"{'='*60}")
        
        target_hour = get_target_hour()
        print(f"🎯 Target hour: {format_hour_key(target_hour)} (3 hours ago)")
        print(f"📍 Current hour: {format_hour_key(current_hour)}")
        
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
                    print(f"⏳ Waiting 60 seconds before retrying...")
                    time.sleep(60)
                    # Don't update current_hour, will retry in next cycle
                    break
                    
            except Exception as e:
                print(f"❌ Failed to process {format_hour_key(current_hour)}: {e}")
                print(f"⏳ Waiting 60 seconds before retrying...")
                time.sleep(60)
                # Don't update current_hour, will retry in next cycle
                break
        
        if processed_in_cycle > 0:
            print(f"\n✅ Cycle completed: Processed {processed_in_cycle} hours")
        else:
            print(f"\n⏸️  No new data to process (caught up to {format_hour_key(target_hour)})")
        
        # Wait before next check (target time advances with current time)
        wait_seconds = 300  # 5 minutes
        print(f"⏳ Waiting {wait_seconds} seconds before next cycle...")
        time.sleep(wait_seconds)

if __name__ == "__main__":
    # Continuous mode: start from 3 days ago, continuously pull up to 3 hours ago
    try:
        run_continuous_producer()
    except KeyboardInterrupt:
        print("\n\n⚠️  Producer stopped by user")
    except Exception as e:
        print(f"\n\n❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        raise