package com.automq.examples;

/**
 * AutoMQ Example Constants
 * 
 * These constants are optimized for AutoMQ's object storage architecture.
 * AutoMQ writes data directly to object storage instead of local disks,
 * which exhibits higher latency for file creation operations (e.g., P99 latency
 * of ~400ms when writing 4MiB files to S3). These configurations help optimize
 * throughput and performance for AutoMQ's characteristics.
 */
public class AutoMQExampleConstants {

    /**
     * During testing, you can replace the following configuration with the one in your environment.
     * BOOTSTRAP_SERVERS can be configured via environment variable or defaults to localhost:9092
     */
    public static final String BOOTSTRAP_SERVERS = System.getenv().getOrDefault("BOOTSTRAP_SERVERS", "localhost:9092");
    
    // Topic and Consumer Group Configuration
    public static final String TOPIC_NAME = "test-topic";
    public static final String TRANSACTIONAL_TOPIC_NAME = "trans-test-topic";
    public static final String CONSUMER_GROUP_ID = "test-consumer-group";
    public static final String TRANSACTIONAL_CONSUMER_GROUP_ID = "trans-consumer-group";
    
    /**
     * Number of retries for failed requests.
     * Helps handle transient failures in object storage operations.
     */
    public static final int RETRIES_CONFIG = 3;

    // Producer Configuration - Optimized for AutoMQ's object storage architecture
    
    /**
     * Metadata refresh interval (60 seconds).
     * The forced refresh time for metadata to prevent routing errors due to metadata expiration.
     * Recommended value for AutoMQ to balance metadata freshness and performance.
     */
    public static final int METADATA_MAX_AGE_MS = 60000;
    
    /**
     * Batch size for producer (1MB).
     * The maximum number of bytes in a single batch, directly affecting the number of network requests and throughput.
     */
    public static final int BATCH_SIZE = 1048576;
    
    /**
     * Linger time for batching (100ms).
     * The delay time for the Producer to batch send messages, enhancing the efficiency
     * of each request by accumulating more messages. This helps optimize for AutoMQ's
     * object storage latency characteristics.
     */
    public static final int LINGER_MS = 100;
    
    /**
     * Maximum request size (16MB).
     * The maximum number of bytes in a single request, limiting the size of messages
     * the Producer can send.
     */
    public static final int MAX_REQUEST_SIZE = 16777216;
    
    /**
     * Acknowledgment configuration.
     * The server responds to the client only after the data has been persisted to cloud storage.
     * In the event of a server crash, successfully acknowledged messages will not be lost.
     */
    public static final String ACKS_CONFIG = "all";

    // Consumer Configuration - Optimized for AutoMQ
    
    /**
     * Isolation level for transactional reads.
     * "read_committed" ensures only committed messages are read in transactional scenarios.
     */
    public static final String ISOLATION_LEVEL = "read_committed";
    
    /**
     * Auto offset reset strategy.
     * "earliest" starts reading from the beginning of the topic when no offset is found.
     */
    public static final String AUTO_OFFSET_RESET = "earliest";
    
    /**
     * Maximum partition fetch bytes (8MB).
     * Limits the maximum amount of data returned in a Fetch request from a single partition,
     * working together with fetch.max.bytes to control fetch granularity.
     */
    public static final int MAX_PARTITION_FETCH_BYTES = 8388608;
}