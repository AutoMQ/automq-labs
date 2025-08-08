#ifndef TRANSACTIONAL_MESSAGE_EXAMPLE_H
#define TRANSACTIONAL_MESSAGE_EXAMPLE_H

// Note: This example requires librdkafka to be installed
// Install with: brew install librdkafka
// Then uncomment the following line:
// #include <rdkafkacpp.h>

#include <string>
#include <vector>
#include <chrono>
#include <atomic>
#include <mutex>

struct TransactionMetrics {
    std::atomic<int> transactionsCommitted{0};
    std::atomic<int> transactionsAborted{0};
    std::atomic<int> messagesInTransactions{0};
    std::atomic<int> messagesConsumed{0};
    std::atomic<long long> totalTransactionLatency{0};
    std::chrono::high_resolution_clock::time_point startTime;
    std::chrono::high_resolution_clock::time_point endTime;
    std::chrono::high_resolution_clock::time_point consumeStartTime;
    std::chrono::high_resolution_clock::time_point consumeEndTime;
    
    void reset() {
        transactionsCommitted = 0;
        transactionsAborted = 0;
        messagesInTransactions = 0;
        messagesConsumed = 0;
        totalTransactionLatency = 0;
    }
    
    void printMetrics() const;
};

class TransactionalMessageExample {
public:
    static void run();
    
private:
    static void runTransactionalProducer(TransactionMetrics& metrics);
    static void runTransactionalConsumer(TransactionMetrics& metrics);
    // Note: These methods require librdkafka
    // static RdKafka::Producer* createTransactionalProducer();
    // static RdKafka::KafkaConsumer* createTransactionalConsumer();
    static std::string generateTransactionId();
    static std::string generateMessage(int size);
    static long long getCurrentTimeMillis();
    static bool simulateTransactionSuccess(); // Simulate transaction commit/abort
};

#endif // TRANSACTIONAL_MESSAGE_EXAMPLE_H