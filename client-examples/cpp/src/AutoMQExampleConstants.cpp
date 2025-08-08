#include "AutoMQExampleConstants.h"
#include <cstdlib>

// Get environment variable or return default value
std::string getEnvOrDefault(const char* envVar, const std::string& defaultValue) {
    const char* value = std::getenv(envVar);
    return value ? std::string(value) : defaultValue;
}

int getEnvOrDefault(const char* envVar, int defaultValue) {
    const char* value = std::getenv(envVar);
    return value ? std::stoi(value) : defaultValue;
}

// Kafka configuration
const std::string AutoMQExampleConstants::BOOTSTRAP_SERVERS = getEnvOrDefault("BOOTSTRAP_SERVERS", "localhost:9092");
const std::string AutoMQExampleConstants::TOPIC_NAME = getEnvOrDefault("TOPIC_NAME", "automq-cpp-example-topic");
const std::string AutoMQExampleConstants::CONSUMER_GROUP_ID = getEnvOrDefault("CONSUMER_GROUP_ID", "automq-cpp-example-group");

// Message configuration
const int AutoMQExampleConstants::MESSAGE_COUNT = getEnvOrDefault("MESSAGE_COUNT", 10000);
const int AutoMQExampleConstants::MESSAGE_SIZE = getEnvOrDefault("MESSAGE_SIZE", 1024);
const std::string AutoMQExampleConstants::MESSAGE_KEY_PREFIX = "key-";
const std::string AutoMQExampleConstants::MESSAGE_VALUE_PREFIX = "value-";

// Performance tuning for AutoMQ
const int AutoMQExampleConstants::BATCH_SIZE = getEnvOrDefault("BATCH_SIZE", 65536);
const int AutoMQExampleConstants::LINGER_MS = getEnvOrDefault("LINGER_MS", 100);
const int AutoMQExampleConstants::BUFFER_MEMORY = getEnvOrDefault("BUFFER_MEMORY", 67108864); // 64MB
const int AutoMQExampleConstants::MAX_REQUEST_SIZE = getEnvOrDefault("MAX_REQUEST_SIZE", 10485760); // 10MB

// Consumer configuration
const int AutoMQExampleConstants::MAX_POLL_RECORDS = getEnvOrDefault("MAX_POLL_RECORDS", 1000);
const int AutoMQExampleConstants::FETCH_MIN_BYTES = getEnvOrDefault("FETCH_MIN_BYTES", 1024);
const int AutoMQExampleConstants::FETCH_MAX_WAIT_MS = getEnvOrDefault("FETCH_MAX_WAIT_MS", 1000);

// Transaction configuration
const std::string AutoMQExampleConstants::TRANSACTIONAL_ID_PREFIX = "automq-cpp-tx-";
const int AutoMQExampleConstants::TRANSACTION_TIMEOUT_MS = getEnvOrDefault("TRANSACTION_TIMEOUT_MS", 60000);