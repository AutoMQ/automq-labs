package com.automq.examples;

public class AutoMQExampleConstants {

    /**
     * During testing, you can replace the following configuration with the one in your environment.
     * BOOTSTRAP_SERVERS can be configured via environment variable or defaults to localhost:9092
     */
    public static final String BOOTSTRAP_SERVERS = System.getenv().getOrDefault("BOOTSTRAP_SERVERS", "localhost:9092");
    public static final String TOPIC_NAME = "test-topic";
    public static final String TRANSACTIONAL_TOPIC_NAME = "trans-test-topic";
    public static final String CONSUMER_GROUP_ID = "test-consumer-group";
    public static final String TRANSACTIONAL_CONSUMER_GROUP_ID = "trans-consumer-group";
    public static final int RETRIES_CONFIG = 3;

    public static final int METADATA_MAX_AGE_MS = 60000;
    public static final int BATCH_SIZE = 1048576;
    public static final int LINGER_MS = 100;
    public static final int MAX_REQUEST_SIZE = 16777216;
    public static final String ACKS_CONFIG = "all";

    public static final String ISOLATION_LEVEL = "read_committed";
    public static final String AUTO_OFFSET_RESET = "earliest";
    public static final int MAX_PARTITION_FETCH_BYTES = 8388608;
}