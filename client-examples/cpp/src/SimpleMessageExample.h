#ifndef SIMPLE_MESSAGE_EXAMPLE_H
#define SIMPLE_MESSAGE_EXAMPLE_H

#include "AutoMQExampleConstants.h"
#include <rdkafkacpp.h>
#include <iostream>
#include <chrono>
#include <string>
#include <sstream>
#include <thread>
#include <memory>
#include <vector>
#include <atomic>
#include <mutex>

// Forward declarations
namespace RdKafka {
    class Producer;
    class KafkaConsumer;
    class Conf;
}

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
    
    // Batch consumption method for improved performance
    static std::vector<RdKafka::Message*> consumeBatch(
        RdKafka::KafkaConsumer* consumer, size_t batch_size, int batch_timeout);
    // librdkafka methods
    static RdKafka::Producer* createProducer();
    static RdKafka::KafkaConsumer* createConsumer();
    static RdKafka::Conf* createProducerConfig();
    static RdKafka::Conf* createConsumerConfig();
    static std::string generateMessage(int size);
    static long long getCurrentTimeMillis();
};

#endif // SIMPLE_MESSAGE_EXAMPLE_H