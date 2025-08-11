#include "SimpleMessageExample.h"
#include "AutoMQExampleConstants.h"
#include <iostream>
#include <string>
#include <cstdlib>

void printUsage(const char* programName) {
    std::cout << "AutoMQ C++ Client Examples" << std::endl;
    std::cout << "Usage: " << programName << " [example_type]" << std::endl;
    std::cout << "\nAvailable examples:" << std::endl;
    std::cout << "  simple      - Simple message producer and consumer example" << std::endl;
    std::cout << "\nEnvironment variables:" << std::endl;
    std::cout << "  BOOTSTRAP_SERVERS   - Kafka bootstrap servers (default: localhost:9092)" << std::endl;
    std::cout << "  TOPIC_NAME          - Topic name (default: automq-cpp-example-topic)" << std::endl;
    std::cout << "  MESSAGE_COUNT       - Number of messages (default: 10000)" << std::endl;
    std::cout << "  MESSAGE_SIZE        - Message size in bytes (default: 1024)" << std::endl;
    std::cout << "\nExamples:" << std::endl;
    std::cout << "  " << programName << " simple" << std::endl;
    std::cout << "  BOOTSTRAP_SERVERS=localhost:9092 " << programName << " simple" << std::endl;
}

void printConfiguration() {
    std::cout << "\n=== Configuration ===" << std::endl;
    std::cout << "Bootstrap Servers: " << AutoMQExampleConstants::BOOTSTRAP_SERVERS << std::endl;
    std::cout << "Topic Name: " << AutoMQExampleConstants::TOPIC_NAME << std::endl;
    std::cout << "Consumer Group: " << AutoMQExampleConstants::CONSUMER_GROUP_ID << std::endl;
    std::cout << "Message Count: " << AutoMQExampleConstants::MESSAGE_COUNT << std::endl;
    std::cout << "Message Size: " << AutoMQExampleConstants::MESSAGE_SIZE << " bytes" << std::endl;
    std::cout << "Batch Size: " << AutoMQExampleConstants::BATCH_SIZE << " bytes" << std::endl;
    std::cout << "Linger MS: " << AutoMQExampleConstants::LINGER_MS << " ms" << std::endl;
    std::cout << "Buffer Memory: " << AutoMQExampleConstants::BUFFER_MEMORY << " bytes" << std::endl;
    std::cout << "====================\n" << std::endl;
}

int main(int argc, char* argv[]) {
    std::cout << "AutoMQ C++ Client Examples" << std::endl;
    std::cout << "===========================" << std::endl;
    
    std::string exampleType = "simple";
    if (argc > 1) {
        exampleType = argv[1];
    }
    
    if (exampleType == "help" || exampleType == "-h" || exampleType == "--help") {
        printUsage(argv[0]);
        return 0;
    }
    
    printConfiguration();
    
    try {
        if (exampleType == "simple") {
            std::cout << "Running Simple Message Example...\n" << std::endl;
            SimpleMessageExample::run();
        } else {
            std::cerr << "Unknown example type: " << exampleType << std::endl;
            std::cerr << "Use 'help' to see available options." << std::endl;
            return 1;
        }
    } catch (const std::exception& e) {
        std::cerr << "Error running example: " << e.what() << std::endl;
        return 1;
    }
    
    return 0;
}