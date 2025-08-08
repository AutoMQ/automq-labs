#include "TransactionalMessageExample.h"
#include "AutoMQExampleConstants.h"
#include <iostream>
#include <thread>
#include <iomanip>
#include <random>
#include <uuid/uuid.h>

void TransactionMetrics::printMetrics() const {
    auto produceDuration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    auto consumeDuration = std::chrono::duration_cast<std::chrono::milliseconds>(consumeEndTime - consumeStartTime).count();
    
    std::cout << "\n=== Transaction Performance Metrics ===" << std::endl;
    std::cout << "Transactions committed: " << transactionsCommitted << std::endl;
    std::cout << "Transactions aborted: " << transactionsAborted << std::endl;
    std::cout << "Messages in transactions: " << messagesInTransactions << std::endl;
    std::cout << "Messages consumed: " << messagesConsumed << std::endl;
    std::cout << "Transaction duration: " << produceDuration << " ms" << std::endl;
    std::cout << "Consume duration: " << consumeDuration << " ms" << std::endl;
    
    if (transactionsCommitted > 0) {
        double transactionRate = (double)transactionsCommitted * 1000.0 / produceDuration;
        double avgTransactionLatency = (double)totalTransactionLatency / transactionsCommitted;
        std::cout << "Transaction rate: " << std::fixed << std::setprecision(2) << transactionRate << " tx/s" << std::endl;
        std::cout << "Average transaction latency: " << std::fixed << std::setprecision(2) << avgTransactionLatency << " ms" << std::endl;
    }
    
    if (messagesConsumed > 0) {
        double consumeRate = (double)messagesConsumed * 1000.0 / consumeDuration;
        std::cout << "Consume rate: " << std::fixed << std::setprecision(2) << consumeRate << " msg/s" << std::endl;
    }
    
    double successRate = (double)transactionsCommitted / (transactionsCommitted + transactionsAborted) * 100.0;
    std::cout << "Transaction success rate: " << std::fixed << std::setprecision(1) << successRate << "%" << std::endl;
    std::cout << "======================================\n" << std::endl;
}

void TransactionalMessageExample::run() {
    std::cout << "Starting Transactional Message Example..." << std::endl;
    std::cout << "Bootstrap servers: " << AutoMQExampleConstants::BOOTSTRAP_SERVERS << std::endl;
    std::cout << "Topic: " << AutoMQExampleConstants::TOPIC_NAME << std::endl;
    std::cout << "Transaction timeout: " << AutoMQExampleConstants::TRANSACTION_TIMEOUT_MS << " ms" << std::endl;
    
    std::cout << "\nNOTE: This is a demo version. To run with actual Kafka:" << std::endl;
    std::cout << "1. Install librdkafka: brew install librdkafka" << std::endl;
    std::cout << "2. Uncomment the #include <rdkafkacpp.h> line in the header" << std::endl;
    std::cout << "3. Recompile with: g++ -std=c++11 -lrdkafka++ -o example src/*.cpp" << std::endl;
    std::cout << "\nRunning transaction simulation...\n" << std::endl;
    
    TransactionMetrics metrics;
    metrics.reset();
    
    // Run transactional producer and consumer in parallel
    std::thread producerThread([&metrics]() {
        runTransactionalProducer(metrics);
    });
    
    std::thread consumerThread([&metrics]() {
        // Wait a bit for producer to start
        std::this_thread::sleep_for(std::chrono::seconds(3));
        runTransactionalConsumer(metrics);
    });
    
    producerThread.join();
    consumerThread.join();
    
    metrics.printMetrics();
}

void TransactionalMessageExample::runTransactionalProducer(TransactionMetrics& metrics) {
    std::cout << "Starting transactional producer simulation..." << std::endl;
    
    metrics.startTime = std::chrono::high_resolution_clock::now();
    
    // Simulate transactions with batches of messages
    int transactionCount = AutoMQExampleConstants::MESSAGE_COUNT / 100; // 100 messages per transaction
    int messagesPerTransaction = 100;
    
    for (int txId = 0; txId < transactionCount; ++txId) {
        std::string transactionId = generateTransactionId();
        
        std::cout << "Starting transaction " << (txId + 1) << "/" << transactionCount 
                  << " (ID: " << transactionId << ")" << std::endl;
        
        long long txStartTime = getCurrentTimeMillis();
        
        // Simulate transaction begin
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        
        bool transactionSuccess = true;
        
        // Produce messages within transaction
        for (int i = 0; i < messagesPerTransaction; ++i) {
            int messageId = txId * messagesPerTransaction + i;
            std::string key = AutoMQExampleConstants::MESSAGE_KEY_PREFIX + std::to_string(messageId);
            std::string value = generateMessage(AutoMQExampleConstants::MESSAGE_SIZE);
            
            // Add transaction metadata
            value += "|tx:" + transactionId + "|msg:" + std::to_string(i);
            
            // Simulate message production within transaction
            std::this_thread::sleep_for(std::chrono::microseconds(500 + (rand() % 1000)));
            
            // Simulate occasional message failure (5% chance)
            if (rand() % 100 < 5) {
                std::cout << "  Message " << i << " failed, will abort transaction" << std::endl;
                transactionSuccess = false;
                break;
            }
            
            metrics.messagesInTransactions++;
        }
        
        // Simulate transaction commit/abort
        std::this_thread::sleep_for(std::chrono::milliseconds(5 + (rand() % 10)));
        
        long long txEndTime = getCurrentTimeMillis();
        long long txLatency = txEndTime - txStartTime;
        
        if (transactionSuccess && simulateTransactionSuccess()) {
            std::cout << "  Transaction committed successfully (" << txLatency << "ms)" << std::endl;
            metrics.transactionsCommitted++;
            metrics.totalTransactionLatency += txLatency;
        } else {
            std::cout << "  Transaction aborted (" << txLatency << "ms)" << std::endl;
            metrics.transactionsAborted++;
            // In real scenario, messages would be rolled back
            metrics.messagesInTransactions -= messagesPerTransaction;
        }
        
        // Brief pause between transactions
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    
    metrics.endTime = std::chrono::high_resolution_clock::now();
    std::cout << "Transactional producer simulation finished" << std::endl;
}

void TransactionalMessageExample::runTransactionalConsumer(TransactionMetrics& metrics) {
    std::cout << "Starting transactional consumer simulation..." << std::endl;
    
    metrics.consumeStartTime = std::chrono::high_resolution_clock::now();
    
    // Only consume committed messages
    int expectedMessages = metrics.transactionsCommitted * 100;
    
    for (int i = 0; i < expectedMessages; ++i) {
        // Simulate message consumption with transaction isolation
        std::this_thread::sleep_for(std::chrono::microseconds(800 + (rand() % 400)));
        
        // Simulate processing transactional message
        // In real scenario, consumer would read only committed messages
        
        metrics.messagesConsumed++;
        
        if ((i + 1) % 500 == 0) {
            std::cout << "Consumed " << (i + 1) << " committed messages" << std::endl;
        }
    }
    
    metrics.consumeEndTime = std::chrono::high_resolution_clock::now();
    std::cout << "Transactional consumer simulation finished" << std::endl;
}

std::string TransactionalMessageExample::generateTransactionId() {
    // Generate a simple transaction ID
    static int counter = 0;
    return AutoMQExampleConstants::TRANSACTIONAL_ID_PREFIX + std::to_string(++counter) + "-" + std::to_string(getCurrentTimeMillis());
}

std::string TransactionalMessageExample::generateMessage(int size) {
    static std::random_device rd;
    static std::mt19937 gen(rd());
    static std::uniform_int_distribution<> dis('a', 'z');
    
    std::string message;
    message.reserve(size);
    
    for (int i = 0; i < size - 100; ++i) { // Reserve space for transaction metadata
        message += static_cast<char>(dis(gen));
    }
    
    return message;
}

long long TransactionalMessageExample::getCurrentTimeMillis() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::high_resolution_clock::now().time_since_epoch()).count();
}

bool TransactionalMessageExample::simulateTransactionSuccess() {
    // Simulate 90% transaction success rate
    return (rand() % 100) < 90;
}