import json
import gzip
import shutil
import os
import requests
import dateutil.parser
from confluent_kafka import Producer
from confluent_kafka.schema_registry import SchemaRegistryClient
from confluent_kafka.schema_registry.avro import AvroSerializer
from confluent_kafka.serialization import SerializationContext, MessageField

# ================= 配置部分 =================
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'automq:9092')
SCHEMA_REGISTRY_URL = os.getenv('SCHEMA_REGISTRY_URL', 'http://schema-registry:8081')
TOPIC_NAME = os.getenv('TOPIC_NAME', 'github_events_iceberg')

# 读取 Avro Schema
schema_path = os.path.join(os.path.dirname(__file__), 'github_event.avsc')
with open(schema_path, 'r') as f:
    SCHEMA_STR = f.read()

class GithubEventMapper:
    """负责将复杂的 GH JSON 映射到扁平的 Avro 字典"""
    
    @staticmethod
    def to_timestamp(time_str):
        if not time_str: return None
        dt = dateutil.parser.parse(time_str)
        return int(dt.timestamp() * 1000) # 转为毫秒

    @staticmethod
    def map_event(raw):
        payload = raw.get('payload', {})
        t = raw.get('type')

        # 1. 基础字段
        record = {
            "id": raw.get("id"),
            "type": t,
            "created_at": GithubEventMapper.to_timestamp(raw.get("created_at")),
            "actor_login": raw.get("actor", {}).get("login"),
            "repo_name": raw.get("repo", {}).get("name")
        }
            
        return record

def main(date_str, hour):
    # Setup Kafka
    schema_registry_client = SchemaRegistryClient({'url': SCHEMA_REGISTRY_URL})
    avro_serializer = AvroSerializer(schema_registry_client, SCHEMA_STR)
    
    producer = Producer({'bootstrap.servers': KAFKA_BOOTSTRAP_SERVERS})
    
    def delivery_report(err, msg):
        if err: print(f"Delivery failed: {err}")

    # Download & Process
    file_name = f"{date_str}-{hour}.json.gz"
    url = f"https://data.gharchive.org/{file_name}"
    print(f"Processing: {url}")

    try:
        # 流式下载 + 解压
        with requests.get(url, stream=True) as r:
            # 这里的逻辑是先存成文件再读，防止内存溢出
            with open(file_name, 'wb') as f:
                shutil.copyfileobj(r.raw, f)
        
        count = 0
        with gzip.open(file_name, 'rt', encoding='utf-8') as f:
            for line in f:
                if not line.strip(): continue
                
                try:
                    raw_json = json.loads(line)

                    print(raw_json)
                    # 核心转换
                    avro_record = GithubEventMapper.map_event(raw_json)
                    
                    producer.produce(
                        topic=TOPIC_NAME,
                        key=str(avro_record['id']),
                        value=avro_serializer(avro_record, SerializationContext(TOPIC_NAME, MessageField.VALUE)),
                        on_delivery=delivery_report
                    )

                    count += 1
                    if count % 2000 == 0:
                        producer.poll(0)
                        print(f"Sent {count} events...")
                        
                except Exception as e:
                    print(f"Error processing line: {e}")
                    continue
        
        producer.flush()
        print(f"Total {count} events sent successfully.")

    finally:
        if os.path.exists(file_name):
            os.remove(file_name)

if __name__ == "__main__":
    import sys
    # 优先使用命令行参数，其次使用环境变量，最后使用默认值
    if len(sys.argv) >= 3:
        date_str = sys.argv[1]
        hour = sys.argv[2]
    else:
        date_str = os.getenv('EVENT_DATE', '2025-01-01')
        hour = os.getenv('EVENT_HOUR', '15')

    print(f"Starting producer for {date_str} hour {hour}")
    main(date_str, hour)