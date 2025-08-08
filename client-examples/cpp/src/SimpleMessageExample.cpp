#include "SimpleMessageExample.h"
#include "AutoMQExampleConstants.h"
#include <iostream>
#include <thread>
#include <iomanip>
#include <random>

void PerformanceMetrics::printMetrics() const {
    auto produceDuration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    auto consumeDuration = std::chrono::duration_cast<std::chrono::milliseconds>(consumeEndTime - consumeStartTime).count();
    
    std::cout << "\n=== Performance Metrics ===" << std::endl;
    std::cout << "Messages sent: " << messagesSent << std::endl;
    std::cout << "Messages received: " << messagesReceived << std::endl;
    std::cout << "Produce duration: " << produceDuration << " ms" << std::endl;
    std::cout << "Consume duration: " << consumeDuration << " ms" << std::endl;
    
    if (messagesSent > 0) {
        double produceRate = (double)messagesSent * 1000.0 / produceDuration;
        double avgProduceLatency = (double)totalProduceLatency / messagesSent;
        std::cout << "Produce rate: " << std::fixed << std::setprecision(2) << produceRate << " msg/s" << std::endl;
        std::cout << "Average produce latency: " << std::fixed << std::setprecision(2) << avgProduceLatency << " ms" << std::endl;
    }
    
    if (messagesReceived > 0) {
        double consumeRate = (double)messagesReceived * 1000.0 / consumeDuration;
        double avgEndToEndLatency = (double)totalEndToEndLatency / messagesReceived;
        std::cout << "Consume rate: " << std::fixed << std::setprecision(2) << consumeRate << " msg/s" << std::endl;
        std::cout << "Average end-to-end latency: " << std::fixed << std::setprecision(2) << avgEndToEndLatency << " ms" << std::endl;
    }
    std::cout << "===========================\n" << std::endl;
}

void SimpleMessageExample::run() {
    std::cout << "Starting Simple Message Example..." << std::endl;
    std::cout << "Bootstrap servers: " << AutoMQExampleConstants::BOOTSTRAP_SERVERS << std::endl;
    std::cout << "Topic: " << AutoMQExampleConstants::TOPIC_NAME << std::endl;
    std::cout << "Message count: " << AutoMQExampleConstants::MESSAGE_COUNT << std::endl;
    std::cout << "Message size: " << AutoMQExampleConstants::MESSAGE_SIZE << " bytes" << std::endl;
    
    std::cout << "\nNOTE: This is a demo version. To run with actual Kafka:" << std::endl;
    std::cout << "1. Install librdkafka: brew install librdkafka" << std::endl;
    std::cout << "2. Uncomment the #include <rdkafkacpp.h> line in the header" << std::endl;
    std::cout << "3. Recompile with: g++ -std=c++11 -lrdkafka++ -o example src/*.cpp" << std::endl;
    std::cout << "\nRunning simulation...\n" << std::endl;
    
    PerformanceMetrics metrics;
    metrics.reset();
    
    // Run producer and consumer simulation in parallel
    std::thread producerThread([&metrics]() {
        runProducer(metrics);
    });
    
    std::thread consumerThread([&metrics]() {
        // Wait a bit for producer to start
        std::this_thread::sleep_for(std::chrono::seconds(2));
        runConsumer(metrics);
    });
    
    producerThread.join();
    consumerThread.join();
    
    metrics.printMetrics();
}

void SimpleMessageExample::runProducer(PerformanceMetrics& metrics) {
    std::cout << "Starting producer simulation..." << std::endl;
    
    metrics.startTime = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < AutoMQExampleConstants::MESSAGE_COUNT; ++i) {
        std::string key = AutoMQExampleConstants::MESSAGE_KEY_PREFIX + std::to_string(i);
        std::string value = generateMessage(AutoMQExampleConstants::MESSAGE_SIZE);
        
        // Simulate message production
        long long sendTime = getCurrentTimeMillis();
        
        // Simulate network latency (1-5ms)
        std::this_thread::sleep_for(std::chrono::microseconds(1000 + (rand() % 4000)));
        
        long long currentTime = getCurrentTimeMillis();
        long long latency = currentTime - sendTime;
        metrics.totalProduceLatency += latency;
        metrics.messagesSent++;
        
        if ((i + 1) % 1000 == 0) {
            std::cout << "Produced " << (i + 1) << " messages" << std::endl;
        }
    }
    
    metrics.endTime = std::chrono::high_resolution_clock::now();
    std::cout << "Producer simulation finished" << std::endl;
}

void SimpleMessageExample::runConsumer(PerformanceMetrics& metrics) {
    std::cout << "Starting consumer simulation..." << std::endl;
    
    metrics.consumeStartTime = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < AutoMQExampleConstants::MESSAGE_COUNT; ++i) {
        // Simulate message consumption
        long long receiveTime = getCurrentTimeMillis();
        
        // Simulate processing time (0.5-2ms)
        std::this_thread::sleep_for(std::chrono::microseconds(500 + (rand() % 1500)));
        
        // Simulate end-to-end latency (5-15ms)
        long long endToEndLatency = 5 + (rand() % 10);
        metrics.totalEndToEndLatency += endToEndLatency;
        metrics.messagesReceived++;
        
        if ((i + 1) % 1000 == 0) {
            std::cout << "Consumed " << (i + 1) << " messages" << std::endl;
        }
    }
    
    metrics.consumeEndTime = std::chrono::high_resolution_clock::now();
    std::cout << "Consumer simulation finished" << std::endl;
}

std::string SimpleMessageExample::generateMessage(int size) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis('a', 'z');
    
    std::string message;
    message.reserve(size);
    
    for (int i = 0; i < size - 50; ++i) { // Reserve space for metadata
        message += static_cast<char>(dis(gen));
    }
    
    return message;
}

long long SimpleMessageExample::getCurrentTimeMillis() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now().time_since_epoch()).count();
}