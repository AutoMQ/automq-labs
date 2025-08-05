import os

"""
AutoMQ Example Constants

These constants are optimized for AutoMQ's object storage architecture.
AutoMQ writes data directly to object storage instead of local disks,
which exhibits higher latency for file creation operations (e.g., P99 latency
of ~400ms when writing 4MiB files to S3). These configurations help optimize
throughput and performance for AutoMQ's characteristics.

Using kafka-python client - pure Python implementation without external dependencies.
"""

class AutoMQExampleConstants:
    """
    During testing, you can replace the following configuration with the one in your environment.
    BOOTSTRAP_SERVERS can be configured via environment variable or defaults to localhost:9092
    """
    BOOTSTRAP_SERVERS = os.getenv('BOOTSTRAP_SERVERS', 'localhost:9092').split(',')
    
    # Topic and Consumer Group Configuration
    TOPIC_NAME = 'test-topic-py'
    CONSUMER_GROUP_ID = 'test-consumer-group-py'
    
    # Producer Configuration - Optimized for AutoMQ's object storage architecture
    
    # Number of retries for failed requests
    # Helps handle transient failures in object storage operations
    RETRIES = 3
    
    # Metadata refresh interval (60 seconds)
    # The forced refresh time for metadata to prevent routing errors due to metadata expiration
    # Recommended value for AutoMQ to balance metadata freshness and performance
    METADATA_MAX_AGE_MS = 60000
    
    # Batch size for producer (1MB)
    # The maximum number of bytes in a single batch, directly affecting the number of network requests and throughput
    BATCH_SIZE = 1048576
    
    # Linger time for batching (100ms)
    # The delay time for the Producer to batch send messages, enhancing the efficiency
    # of each request by accumulating more messages. This helps optimize for AutoMQ's
    # object storage latency characteristics
    LINGER_MS = 100
    
    # Maximum request size (16MB)
    # The maximum number of bytes in a single request, limiting the size of messages
    # the Producer can send
    MAX_REQUEST_SIZE = 16777216
    
    # Acknowledgment configuration
    # 0: Producer doesn't wait for acknowledgment (fastest, least durable)
    # 1: Producer waits for leader acknowledgment
    # 'all': Producer waits for all in-sync replicas acknowledgment (slowest, most durable)
    ACKS = 'all'
    
    # Consumer Configuration - Optimized for AutoMQ
    
    # Auto offset reset strategy
    # "earliest" starts reading from the beginning of the topic when no offset is found
    AUTO_OFFSET_RESET = 'earliest'
    
    # Maximum partition fetch bytes (8MB)
    # Limits the maximum amount of data returned in a Fetch request from a single partition
    MAX_PARTITION_FETCH_BYTES = 8388608
    
    # Session timeout for consumer (30 seconds)
    SESSION_TIMEOUT_MS = 30000
    
    # Heartbeat interval (10 seconds)
    HEARTBEAT_INTERVAL_MS = 10000
    
    # Consumer timeout (1 second)
    # Time to wait for messages before timing out
    CONSUMER_TIMEOUT_MS = 1000
    
    # Enable auto commit for consumer
    ENABLE_AUTO_COMMIT = True
    
    # Auto commit interval (5 seconds)
    AUTO_COMMIT_INTERVAL_MS = 5000