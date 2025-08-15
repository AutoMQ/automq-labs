#include "SimpleMessageExample.h"
#include "AutoMQExampleConstants.h"
#include <librdkafka/rdkafkacpp.h>
#include <iostream>
#include <thread>
#include <iomanip>
#include <random>
#include <sstream>
#include <cstdlib>
#include <chrono>
#include <string>
#include <vector>

void PerformanceMetrics::printMetrics() const {
    auto produceDuration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
    auto consumeDuration = std::chrono::duration_cast<std::chrono::milliseconds>(consumeEndTime - consumeStartTime).count();
    
    std::cout << "\n=== Performance Metrics ===" << std::endl;
    std::cout << "Messages sent: " << messagesSent << std::endl;
    std::cout << "Messages received: " << messagesReceived << std::endl;
    std::cout << "Produce duration: " << produceDuration << " ms" << std::endl;
    std::cout << "Consume duration: " << consumeDuration << " ms" << std::endl;
    

    
    if (messagesReceived > 0) {
        double consumeRate = (double)messagesReceived * 500.0 / consumeDuration;
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
    std::cout << "\nConnecting to Kafka cluster...\n" << std::endl;
    
    PerformanceMetrics metrics;
    metrics.reset();
    
    // Start consumer subscription to topic first
    std::cout << "Step 1: Starting consumer subscription..." << std::endl;
    std::thread consumerThread([&metrics]() {
        runConsumer(metrics);
    });
    
    // Wait for a while to ensure consumer subscription is completed
    std::this_thread::sleep_for(std::chrono::milliseconds(1000));
    
    // Then start producer to send messages
    std::cout << "Step 2: Starting producer..." << std::endl;
    std::thread producerThread([&metrics]() {
        runProducer(metrics);
    });
    
    consumerThread.join();
    producerThread.join();
    
    metrics.printMetrics();
}

void SimpleMessageExample::runProducer(PerformanceMetrics& metrics) {
    std::cout << "Starting producer..." << std::endl;
    
    RdKafka::Producer* producer = createProducer();
    if (!producer) {
        std::cerr << "Failed to create producer" << std::endl;
        return;
    }
    
    metrics.startTime = std::chrono::high_resolution_clock::now();
    
    for (int i = 0; i < AutoMQExampleConstants::MESSAGE_COUNT; ++i) {
        std::string key = AutoMQExampleConstants::MESSAGE_KEY_PREFIX + std::to_string(i);
        long long sendTime = getCurrentTimeMillis();
        
        // Create JSON message similar to Java version
        std::ostringstream oss;
        oss << "{\"id\":\"msg-" << i << "\",\"timestamp\":" << sendTime 
            << ",\"content\":\"Hello AutoMQ " << i << "\"}";
        std::string value = oss.str();
        
        RdKafka::ErrorCode resp = producer->produce(
            AutoMQExampleConstants::TOPIC_NAME,
            RdKafka::Topic::PARTITION_UA,
            RdKafka::Producer::RK_MSG_COPY,
            const_cast<char*>(value.c_str()), value.size(),
            const_cast<char*>(key.c_str()), key.size(),
            0,
            nullptr
        );
        
        if (resp != RdKafka::ERR_NO_ERROR) {
            std::cerr << "Failed to produce message " << (i + 1) << ": " << RdKafka::err2str(resp) << std::endl;
        } else {
            long long currentTime = getCurrentTimeMillis();
            long long latency = currentTime - sendTime;
            metrics.totalProduceLatency += latency;
            metrics.messagesSent++;
            
            std::cout << "Produced message " << (i + 1) << "/" << AutoMQExampleConstants::MESSAGE_COUNT
                      << ": key=" << key
                      << ", size=" << value.size() << " bytes"
                      << ", latency=" << latency << " ms" << std::endl;
        }
        
        producer->poll(0);
    }
    
    // Wait for all messages to be delivered
    // Increase timeout to ensure all messages are sent
    std::cout << "Flushing producer to ensure all messages are delivered..." << std::endl;
    producer->flush(10000); // Increased timeout to 10 seconds
    
    metrics.endTime = std::chrono::high_resolution_clock::now();
    std::cout << "Producer finished" << std::endl;
    
    delete producer;
}

// Batch consume function inspired by librdkafka official example
std::vector<RdKafka::Message*> SimpleMessageExample::consumeBatch(
    RdKafka::KafkaConsumer* consumer, size_t batch_size, int batch_timeout) {
    std::vector<RdKafka::Message*> msgs;
    msgs.reserve(batch_size);
    
    auto start_time = std::chrono::high_resolution_clock::now();
    int remaining_timeout = batch_timeout;
    
    while (msgs.size() < batch_size && remaining_timeout > 0) {
        RdKafka::Message* msg = consumer->consume(remaining_timeout);
        
        switch (msg->err()) {
        case RdKafka::ERR__TIMED_OUT:
            delete msg;
            return msgs; // Return whatever we have collected
            
        case RdKafka::ERR_NO_ERROR:
            msgs.push_back(msg);
            break;
            
        default:
            std::cerr << "Consumer error: " << msg->errstr() << std::endl;
            delete msg;
            break;
        }
        
        // Update remaining timeout
        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::high_resolution_clock::now() - start_time).count();
        remaining_timeout = batch_timeout - static_cast<int>(elapsed);
    }
    
    return msgs;
}

void SimpleMessageExample::runConsumer(PerformanceMetrics& metrics) {
    std::cout << "Starting consumer..." << std::endl;
    
    RdKafka::KafkaConsumer* consumer = createConsumer();
    if (!consumer) {
        std::cerr << "Failed to create consumer" << std::endl;
        return;
    }
    
    std::vector<std::string> topics;
    topics.push_back(AutoMQExampleConstants::TOPIC_NAME);
    RdKafka::ErrorCode err = consumer->subscribe(topics);
    if (err) {
        std::cerr << "Failed to subscribe to topics: " << RdKafka::err2str(err) << std::endl;
        delete consumer;
        return;
    }
    
    std::cout << "Consumer subscribed to topic: " << AutoMQExampleConstants::TOPIC_NAME << std::endl;
    
    metrics.consumeStartTime = std::chrono::high_resolution_clock::now();
    
    // Use batch consumption for better performance
    const size_t BATCH_SIZE = 100;
    const int BATCH_TIMEOUT = 100; // Reduced from 1000ms to 100ms
    
    while (metrics.messagesReceived < AutoMQExampleConstants::MESSAGE_COUNT) {
        std::vector<RdKafka::Message*> batch = consumeBatch(consumer, BATCH_SIZE, BATCH_TIMEOUT);
        
        for (RdKafka::Message* msg : batch) {
            if (msg->err() == RdKafka::ERR_NO_ERROR) {
                long long receiveTime = getCurrentTimeMillis();
                long long endToEndLatency = receiveTime - msg->timestamp().timestamp;
                
                metrics.totalEndToEndLatency += endToEndLatency;
                int currentCount = ++metrics.messagesReceived;
                
                std::cout << "Received message " << currentCount << "/" << AutoMQExampleConstants::MESSAGE_COUNT
                          << ": key=" << (msg->key() ? *msg->key() : "null")
                          << ", partition=" << msg->partition()
                          << ", offset=" << msg->offset()
                          << ", e2eLatency=" << endToEndLatency << " ms" << std::endl;
            }
            delete msg;
        }
        
        // If we got no messages in this batch, continue to next iteration
        if (batch.empty()) {
            continue;
        }
    }
    
    metrics.consumeEndTime = std::chrono::high_resolution_clock::now();
    std::cout << "Consumer finished" << std::endl;
    
    consumer->close();
    delete consumer;
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

RdKafka::Conf* SimpleMessageExample::createProducerConfig() {
    RdKafka::Conf* conf = RdKafka::Conf::create(RdKafka::Conf::CONF_GLOBAL);
    std::string errstr;
    
    conf->set("bootstrap.servers", AutoMQExampleConstants::BOOTSTRAP_SERVERS, errstr);
    conf->set("acks", "all", errstr);
    conf->set("batch.size", std::to_string(AutoMQExampleConstants::BATCH_SIZE), errstr);
    conf->set("linger.ms", std::to_string(AutoMQExampleConstants::LINGER_MS), errstr);
    conf->set("buffer.memory", std::to_string(AutoMQExampleConstants::BUFFER_MEMORY), errstr);
    conf->set("max.request.size", std::to_string(AutoMQExampleConstants::MAX_REQUEST_SIZE), errstr);
    
    return conf;
}

RdKafka::Conf* SimpleMessageExample::createConsumerConfig() {
    RdKafka::Conf* conf = RdKafka::Conf::create(RdKafka::Conf::CONF_GLOBAL);
    std::string errstr;
    
    conf->set("bootstrap.servers", AutoMQExampleConstants::BOOTSTRAP_SERVERS, errstr);
    conf->set("group.id", AutoMQExampleConstants::CONSUMER_GROUP_ID, errstr);
    conf->set("auto.offset.reset", "earliest", errstr);
    conf->set("max.poll.records", std::to_string(AutoMQExampleConstants::MAX_POLL_RECORDS), errstr);
    conf->set("fetch.min.bytes", std::to_string(AutoMQExampleConstants::FETCH_MIN_BYTES), errstr);
    conf->set("fetch.max.wait.ms", std::to_string(AutoMQExampleConstants::FETCH_MAX_WAIT_MS), errstr);
    
    return conf;
}

RdKafka::Producer* SimpleMessageExample::createProducer() {
    RdKafka::Conf* conf = createProducerConfig();
    std::string errstr;
    
    RdKafka::Producer* producer = RdKafka::Producer::create(conf, errstr);
    if (!producer) {
        std::cerr << "Failed to create producer: " << errstr << std::endl;
        delete conf;
        return nullptr;
    }
    
    delete conf;
    return producer;
}

RdKafka::KafkaConsumer* SimpleMessageExample::createConsumer() {
    RdKafka::Conf* conf = createConsumerConfig();
    std::string errstr;
    
    RdKafka::KafkaConsumer* consumer = RdKafka::KafkaConsumer::create(conf, errstr);
    if (!consumer) {
        std::cerr << "Failed to create consumer: " << errstr << std::endl;
        delete conf;
        return nullptr;
    }
    
    delete conf;
    return consumer;
}