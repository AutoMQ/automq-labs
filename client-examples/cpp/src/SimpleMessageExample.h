#ifndef SIMPLE_MESSAGE_EXAMPLE_H
#define SIMPLE_MESSAGE_EXAMPLE_H

// Note: This example requires librdkafka to be installed
// Install with: brew install librdkafka
// Then uncomment the following line:
// #include <rdkafkacpp.h>

#include <string>
#include <vector>
#include <chrono>
#include <atomic>
#include <mutex>

struct PerformanceMetrics {
    std::atomic<int> messagesSent{0};
    std::atomic<int> messagesReceived{0};
    std::atomic<long long> totalProduceLatency{0};
    std::atomic<long long> totalEndToEndLatency{0};
    std::chrono::high_resolution_clock::time_point startTime;
    std::chrono::high_resolution_clock::time_point endTime;
    std::chrono::high_resolution_clock::time_point consumeStartTime;
    std::chrono::high_resolution_clock::time_point consumeEndTime;
    
    void reset() {
        messagesSent = 0;
        messagesReceived = 0;
        totalProduceLatency = 0;
        totalEndToEndLatency = 0;
    }
    
    void printMetrics() const;
};

class SimpleMessageExample {
public:
    static void run();
    
private:
    static void runProducer(PerformanceMetrics& metrics);
    static void runConsumer(PerformanceMetrics& metrics);
    // Note: These methods require librdkafka
    // static RdKafka::Producer* createProducer();
    // static RdKafka::KafkaConsumer* createConsumer();
    static std::string generateMessage(int size);
    static long long getCurrentTimeMillis();
};

#endif // SIMPLE_MESSAGE_EXAMPLE_H