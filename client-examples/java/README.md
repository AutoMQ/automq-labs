# Java Kafka Client Examples

This directory contains sample code for interacting with Kafka using Java, including regular messages and transactional messages production and consumption.

## Prerequisites

- Java 8+
- Maven 3.6+
- Accessible AutoMQ cluster

## Building the Project

```bash
mvn clean package
```

## Configuration

The `AutoMQExampleConstants` class contains all the configuration parameters used in the examples:

AutoMQ does not rely on local disks and directly writes data to object storage. Compared to writing to local disks, the file creation operation in object storage has higher latency. Therefore, the following parameters can be configured on the client-side. For details, you can refer to the AutoMQ documentation at https://www.automq.com/docs/automq/configuration/performance-tuning-for-client