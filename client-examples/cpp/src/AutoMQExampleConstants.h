#ifndef AUTOMQ_EXAMPLE_CONSTANTS_H
#define AUTOMQ_EXAMPLE_CONSTANTS_H

#include <string>

class AutoMQExampleConstants {
public:
    // Kafka configuration
    static const std::string BOOTSTRAP_SERVERS;
    static const std::string TOPIC_NAME;
    static const std::string CONSUMER_GROUP_ID;
    
    // Message configuration
    static const int MESSAGE_COUNT;
    static const int MESSAGE_SIZE;
    static const std::string MESSAGE_KEY_PREFIX;
    static const std::string MESSAGE_VALUE_PREFIX;
    
    // Performance tuning for AutoMQ
    // AutoMQ does not rely on local disks and directly writes data to object storage.
    // Compared to writing to local disks, the file creation operation in object storage has higher latency.
    // Therefore, the following parameters can be configured on the client-side.
    // For details, refer to AutoMQ documentation: https://www.automq.com/docs/automq/configuration/performance-tuning-for-client
    static const int BATCH_SIZE;
    static const int LINGER_MS;
    static const int BUFFER_MEMORY;
    static const int MAX_REQUEST_SIZE;
    
    // Consumer configuration
    static const int MAX_POLL_RECORDS;
    static const int FETCH_MIN_BYTES;
    static const int FETCH_MAX_WAIT_MS;
    
    // Transaction configuration
    static const std::string TRANSACTIONAL_ID_PREFIX;
    static const int TRANSACTION_TIMEOUT_MS;
};

#endif // AUTOMQ_EXAMPLE_CONSTANTS_H