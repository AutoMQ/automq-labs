import json
import time
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, Any

from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError, KafkaTimeoutError
from loguru import logger

from automq_example_constants import AutoMQExampleConstants


class SimpleMessageExample:
    """
    Simple message example optimized for kafka-python 2.2.15
    Demonstrates both producer and consumer with performance metrics
    """
    
    def __init__(self):
        self.MESSAGE_COUNT = 20
        self.sent_count = 0
        self.received_count = 0
        self.start_time = 0
        self.end_time = 0
        self.first_message_time = 0
        self.last_message_time = 0
        self.total_produce_latency = 0
        self.total_e2e_latency = 0
        self.latency_lock = threading.Lock()
        self.e2e_latency_lock = threading.Lock()
        self.consumer_ready = threading.Event()
        self.all_messages_received = threading.Event()
        
        self.bootstrap_servers = AutoMQExampleConstants.BOOTSTRAP_SERVERS
        self.topic_name = AutoMQExampleConstants.TOPIC_NAME
        self.group_id = AutoMQExampleConstants.CONSUMER_GROUP_ID
    
    def create_producer_config(self) -> Dict[str, Any]:
        """Create producer configuration optimized for AutoMQ and kafka-python 2.2.15"""
        return {
            'bootstrap_servers': self.bootstrap_servers,
            'acks': AutoMQExampleConstants.ACKS,
            'retries': AutoMQExampleConstants.RETRIES,
            'metadata_max_age_ms': AutoMQExampleConstants.METADATA_MAX_AGE_MS,
            'batch_size': AutoMQExampleConstants.BATCH_SIZE,
            'linger_ms': AutoMQExampleConstants.LINGER_MS,
            'max_request_size': AutoMQExampleConstants.MAX_REQUEST_SIZE,
            'value_serializer': lambda v: json.dumps(v).encode('utf-8'),
            'key_serializer': lambda k: k.encode('utf-8') if k else None,
            # Additional configurations for kafka-python 2.2.15
            'request_timeout_ms': 30000,
            'api_version': (2, 0, 0),  # Use stable API version
        }
    
    def create_consumer_config(self) -> Dict[str, Any]:
        """Create consumer configuration optimized for AutoMQ and kafka-python 2.2.15"""
        return {
            'bootstrap_servers': self.bootstrap_servers,
            'group_id': self.group_id,
            'auto_offset_reset': 'latest',  # Start from latest messages for this example
            'metadata_max_age_ms': AutoMQExampleConstants.METADATA_MAX_AGE_MS,
            'max_partition_fetch_bytes': AutoMQExampleConstants.MAX_PARTITION_FETCH_BYTES,
            'session_timeout_ms': AutoMQExampleConstants.SESSION_TIMEOUT_MS,
            'heartbeat_interval_ms': AutoMQExampleConstants.HEARTBEAT_INTERVAL_MS,
            'enable_auto_commit': AutoMQExampleConstants.ENABLE_AUTO_COMMIT,
            'auto_commit_interval_ms': AutoMQExampleConstants.AUTO_COMMIT_INTERVAL_MS,
            'value_deserializer': lambda m: json.loads(m.decode('utf-8')) if m else None,
            'key_deserializer': lambda k: k.decode('utf-8') if k else None,
            # Additional configurations for kafka-python 2.2.15
            'fetch_min_bytes': 1,
            'fetch_max_wait_ms': 500,
            'max_poll_records': 500,
            'api_version': (2, 0, 0),  # Use stable API version
            'request_timeout_ms': 40000,  # 40 second timeout for requests (must be > session_timeout_ms + heartbeat_interval_ms)
            'connections_max_idle_ms': 540000,  # 9 minutes
            'retry_backoff_ms': 100,  # Retry backoff time
        }
    
    def run_producer(self):
        """Run the producer to send messages"""
        config = self.create_producer_config()
        
        try:
            producer = KafkaProducer(**config)
            logger.info(f"Producer started, sending {self.MESSAGE_COUNT} messages...")
            logger.info(f"Producer config: bootstrap_servers={config['bootstrap_servers']}")
            logger.info(f"Target topic: {self.topic_name}")
            
            self.start_time = time.time() * 1000  # Convert to milliseconds
            
            for i in range(self.MESSAGE_COUNT):
                message_id = f"msg-{i}"
                send_time = time.time() * 1000  # Convert to milliseconds
                message_value = {
                    "id": message_id,
                    "timestamp": int(send_time),
                    "content": f"Hello AutoMQ {i}"
                }
                
                # Send message with proper error handling
                try:
                    future = producer.send(
                        topic=self.topic_name,
                        key=message_id,
                        value=message_value
                    )
                    
                    # Get the result to measure latency
                    record_metadata = future.get(timeout=10)
                    ack_time = time.time() * 1000  # Convert to milliseconds
                    latency = ack_time - send_time
                    
                    with self.latency_lock:
                        self.total_produce_latency += latency
                        self.sent_count += 1
                    
                    logger.info(
                        f"Message {self.sent_count}/{self.MESSAGE_COUNT} sent successfully: "
                        f"topic={record_metadata.topic}, partition={record_metadata.partition}, "
                        f"offset={record_metadata.offset}, produce latency={latency:.2f}ms"
                    )
                    
                except KafkaTimeoutError as e:
                    logger.error(f"Timeout sending message {i}: {e}")
                except KafkaError as e:
                    logger.error(f"Kafka error sending message {i}: {e}")
                except Exception as e:
                    logger.error(f"Unexpected error sending message {i}: {e}")
            
            # Ensure all messages are sent
            producer.flush(timeout=10)
            logger.info(f"All {self.MESSAGE_COUNT} messages sent successfully")
            
        except Exception as e:
            logger.error(f"Error occurred while creating producer or sending messages: {e}")
        finally:
            try:
                producer.close(timeout=5)
            except Exception:
                pass
    
    def run_consumer(self):
        """Run the consumer to receive messages using kafka-python 2.2.15 best practices"""
        config = self.create_consumer_config()
        
        try:
            logger.info(f"Creating consumer with config: bootstrap_servers={config['bootstrap_servers']}, group_id={config['group_id']}")
            logger.info(f"Attempting to connect to Kafka cluster...")
            
            consumer = KafkaConsumer(self.topic_name, **config)
            
            logger.info(f"Consumer created successfully!")
            logger.info(f"Consumer subscribed to topic: {self.topic_name}")
            logger.info(f"Consumer config: bootstrap_servers={config['bootstrap_servers']}, group_id={config['group_id']}")
            
            # Wait for partition assignment with timeout
            assignment_timeout = 15  # 15 seconds
            assignment_start = time.time()
            
            while not consumer.assignment() and (time.time() - assignment_start) < assignment_timeout:
                try:
                    # Use poll with minimal max_records to trigger assignment
                    consumer.poll(timeout_ms=100, max_records=1)
                except Exception as e:
                    logger.warning(f"Poll during assignment failed: {e}")
                time.sleep(0.1)
            
            assigned_partitions = consumer.assignment()
            logger.info(f"Consumer assigned to partitions: {assigned_partitions}")
            
            if not assigned_partitions:
                logger.error("No partitions assigned to consumer after timeout")
                return
            
            # Check topic existence
            try:
                partitions = consumer.partitions_for_topic(self.topic_name)
                logger.info(f"Topic '{self.topic_name}' has partitions: {partitions}")
            except Exception as e:
                logger.error(f"Failed to get partition info for topic '{self.topic_name}': {e}")
            
            self.consumer_ready.set()
            
            # Main consumption loop optimized for kafka-python 2.2.15
            poll_timeout_ms = 1000  # 1 second timeout
            max_wait_time = 60  # Maximum wait time: 60 seconds
            start_wait_time = time.time()
            poll_count = 0
            consecutive_empty_polls = 0
            
            while self.received_count < self.MESSAGE_COUNT:
                try:
                    # Poll for messages with timeout
                    message_batch = consumer.poll(timeout_ms=poll_timeout_ms, max_records=100)
                    poll_count += 1
                    
                    if not message_batch:
                        consecutive_empty_polls += 1
                        
                        # Log periodic status
                        if poll_count % 10 == 0:
                            logger.info(f"Poll #{poll_count}: No messages received yet, received {self.received_count}/{self.MESSAGE_COUNT} messages")
                            current_assignment = consumer.assignment()
                            logger.info(f"Current partition assignment: {current_assignment}")
                        
                        # Check if we've been waiting too long
                        current_wait_time = time.time()
                        if current_wait_time - start_wait_time > max_wait_time:
                            logger.warning(f"Consumer timeout after {max_wait_time}s, received {self.received_count}/{self.MESSAGE_COUNT} messages")
                            break
                        
                        # If too many consecutive empty polls, check connection
                        if consecutive_empty_polls > 30:
                            logger.warning(f"Too many consecutive empty polls ({consecutive_empty_polls}), checking connection...")
                            try:
                                consumer.poll(timeout_ms=100, max_records=1)
                            except Exception as e:
                                logger.error(f"Connection check failed: {e}")
                        
                        continue
                    
                    consecutive_empty_polls = 0
                    total_messages = sum(len(msgs) for msgs in message_batch.values())
                    logger.info(f"Poll #{poll_count}: Received message batch with {total_messages} messages")
                    
                    # Process messages from all partitions
                    for topic_partition, messages in message_batch.items():
                        for message in messages:
                            if self.received_count >= self.MESSAGE_COUNT:
                                break
                            
                            # Process the message
                            self.received_count += 1
                            current_time = time.time() * 1000  # Convert to milliseconds
                            
                            # Parse message to get timestamp
                            try:
                                message_data = message.value
                                message_timestamp = message_data.get('timestamp', current_time)
                            except (AttributeError, TypeError, json.JSONDecodeError):
                                message_timestamp = current_time
                            
                            e2e_latency = current_time - message_timestamp
                            
                            if self.received_count == 1:
                                self.first_message_time = current_time
                            
                            with self.e2e_latency_lock:
                                self.total_e2e_latency += e2e_latency
                            
                            logger.info(
                                f"Received message {self.received_count}/{self.MESSAGE_COUNT}: "
                                f"key={message.key}, "
                                f"partition={message.partition}, offset={message.offset}, "
                                f"e2eLatency={e2e_latency:.2f}ms"
                            )
                            
                            if self.received_count == self.MESSAGE_COUNT:
                                self.last_message_time = current_time
                                self.end_time = current_time
                                self.all_messages_received.set()
                                break
                        
                        if self.received_count >= self.MESSAGE_COUNT:
                            break
                
                except KafkaError as e:
                    logger.error(f"Kafka error during polling: {e}")
                    time.sleep(1)  # Brief pause before retrying
                except Exception as e:
                    logger.error(f"Unexpected error during polling: {e}")
                    time.sleep(1)  # Brief pause before retrying
            
        except Exception as e:
            logger.error(f"Error occurred while creating consumer or consuming messages: {e}")
        finally:
            try:
                consumer.close()
            except Exception:
                pass
    
    def print_performance_metrics(self):
        """Print performance metrics"""
        total_time = self.end_time - self.start_time
        consume_time = self.last_message_time - self.first_message_time if self.last_message_time > 0 else 0
        
        avg_produce_latency = self.total_produce_latency / self.sent_count if self.sent_count > 0 else 0
        avg_e2e_latency = self.total_e2e_latency / self.received_count if self.received_count > 0 else 0
        
        metrics = f"""
=== Performance Metrics ===
Total Messages: {self.MESSAGE_COUNT}
Messages Sent: {self.sent_count}
Messages Received: {self.received_count}
Total Time: {total_time:.2f} ms
Consume Time: {consume_time:.2f} ms
Average Produce Latency: {avg_produce_latency:.2f} ms
Average End-to-End Latency: {avg_e2e_latency:.2f} ms
===========================
        """
        
        logger.info(metrics)
    
    def run(self):
        """Run the complete example"""
        logger.info("Starting Simple Message Example (kafka-python 2.2.15)...")
        logger.info(f"Will send and receive {self.MESSAGE_COUNT} messages")
        
        with ThreadPoolExecutor(max_workers=2) as executor:
            try:
                # Start consumer in a separate thread
                consumer_future = executor.submit(self.run_consumer)
                
                # Wait for consumer to be ready
                if not self.consumer_ready.wait(timeout=20):
                    logger.error("Consumer failed to become ready within timeout")
                    return
                
                logger.info("Consumer is ready, starting producer...")
                time.sleep(2)  # Give consumer time to fully initialize
                
                # Start producer
                producer_future = executor.submit(self.run_producer)
                
                # Wait for all messages to be received with timeout
                if self.all_messages_received.wait(timeout=90):
                    logger.info("All messages received successfully")
                else:
                    logger.warning("Not all messages were received within timeout")
                
                # Print performance metrics
                self.print_performance_metrics()
                
            except Exception as e:
                logger.error(f"Error occurred during message example: {e}")
        
        logger.info("Simple Message Example completed.")


if __name__ == "__main__":
    example = SimpleMessageExample()
    example.run()