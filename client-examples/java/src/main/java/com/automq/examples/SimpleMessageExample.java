package com.automq.examples;

import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * Simple message example that demonstrates both producer and consumer with performance metrics
 */
@Slf4j
public class SimpleMessageExample {

    private static final int MESSAGE_COUNT = 20;
    private static final AtomicInteger sentCount = new AtomicInteger(0);
    private static final AtomicInteger receivedCount = new AtomicInteger(0);
    private static volatile long startTime;
    private static volatile long endTime;
    private static volatile long firstMessageTime;
    private static volatile long lastMessageTime;
    private static volatile long totalProduceLatency = 0;
    private static volatile long totalE2ELatency = 0;
    private static final Object latencyLock = new Object();
    private static final Object e2eLatencyLock = new Object();
    private static final String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
    private static final String topicName = AutoMQExampleConstants.TOPIC_NAME;
    private static final String groupId = AutoMQExampleConstants.CONSUMER_GROUP_ID;

    public static void main(String[] args) {
        log.info("Starting Simple Message Example...");
        log.info("Will send and receive {} messages", MESSAGE_COUNT);

        CountDownLatch consumerReady = new CountDownLatch(1);
        CountDownLatch allMessagesReceived = new CountDownLatch(1);

        ExecutorService executor = Executors.newFixedThreadPool(2);

        try {
            // Start consumer in a separate thread
            executor.submit(() -> {
                runConsumer(consumerReady, allMessagesReceived);
            });

            // Wait for consumer to be ready
            consumerReady.await();
            Thread.sleep(2000); // Give consumer time to subscribe

            // Start producer
            executor.submit(() -> {
                runProducer(topicName);
            });

            // Wait for all messages to be received
            allMessagesReceived.await();

            // Print performance metrics
            printPerformanceMetrics();

        } catch (Exception e) {
            log.error("Error occurred during message example", e);
        } finally {
            executor.shutdown();
        }

        log.info("Simple Message Example completed.");
    }

    public static Properties createProducerConfig() {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, AutoMQExampleConstants.BATCH_SIZE);
        props.put(ProducerConfig.LINGER_MS_CONFIG, AutoMQExampleConstants.LINGER_MS);
        props.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, AutoMQExampleConstants.MAX_REQUEST_SIZE);

        return props;
    }

    private static void runProducer(String topicName) {
        Properties props = createProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            log.info("Producer started, sending {} messages...", MESSAGE_COUNT);
            startTime = System.currentTimeMillis();

            for (int i = 0; i < MESSAGE_COUNT; i++) {
                String messageId = "msg-" + i;
                long sendTime = System.currentTimeMillis();
                String messageValue = "{\"id\":\"" + messageId + "\",\"timestamp\":" + sendTime + ",\"content\":\"Hello AutoMQ " + i + "\"}";
                ProducerRecord<String, String> record = new ProducerRecord<>(topicName, messageId, messageValue);
                producer.send(record, createProducerCallback(i, sendTime));
            }

            producer.flush(); // Ensure all messages are sent
            log.info("All {} messages sent successfully", MESSAGE_COUNT);

        } catch (Exception e) {
            log.error("Error occurred while sending messages", e);
        }
    }

    private static Callback createProducerCallback(int messageIndex, long sendTime) {
        return (metadata, exception) -> {
            if (exception == null) {
                long recordTime = System.currentTimeMillis();
                long latency = recordTime - sendTime;
                synchronized (latencyLock) {
                    totalProduceLatency += latency;
                }
                int currentCount = sentCount.incrementAndGet();
                log.info("Message {}/{} sent successfully: topic={}, partition={}, offset={}, produce latency={}ms",
                    currentCount, MESSAGE_COUNT, metadata.topic(), metadata.partition(), metadata.offset(), latency);
            } else {
                log.error("Failed to send message {}", messageIndex, exception);
            }
        };
    }

    public static Properties createConsumerConfig(String bootstrapServers) {

        Properties props = new Properties();

        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ConsumerConfig.MAX_PARTITION_FETCH_BYTES_CONFIG, AutoMQExampleConstants.MAX_PARTITION_FETCH_BYTES);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, AutoMQExampleConstants.AUTO_OFFSET_RESET);

        return props;
    }

    private static void runConsumer(CountDownLatch consumerReady,
        CountDownLatch allMessagesReceived) {
        Properties props = createConsumerConfig(bootstrapServers);

        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(Collections.singletonList(topicName));
            log.info("Consumer subscribed to topic: {}", topicName);
            consumerReady.countDown();

            while (receivedCount.get() < MESSAGE_COUNT) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(1000));

                for (ConsumerRecord<String, String> record : records) {
                    int currentCount = receivedCount.incrementAndGet();
                    long latency = System.currentTimeMillis() - record.timestamp();
                    if (currentCount == 1) {
                        firstMessageTime = System.currentTimeMillis();
                    }
                    synchronized (e2eLatencyLock) {
                        totalE2ELatency += latency;
                    }

                    log.info("Received message {}/{}: key={}, partition={}, offset={}, e2eLatency={} ms",
                        currentCount, MESSAGE_COUNT, record.key(), record.partition(), record.offset(), latency);

                    if (currentCount == MESSAGE_COUNT) {
                        lastMessageTime = System.currentTimeMillis();
                        endTime = System.currentTimeMillis();
                        allMessagesReceived.countDown();
                        break;
                    }
                }
            }

        } catch (Exception e) {
            log.error("Error occurred while consuming messages", e);
        }
    }

    private static void printPerformanceMetrics() {
        long totalTime = endTime - startTime;
        long consumeTime = lastMessageTime - firstMessageTime;
        log.info("=== Performance Metrics ===\n" +
                "Total Messages: {}\n" +
                "Messages Sent: {}\n" +
                "Messages Received: {}\n" +
                "Total Time: {} ms\n" +
                "Consume Time: {} ms\n" +
                "Average Produce Latency: {} ms\n" +
                "Average End-to-End Latency: {} ms\n" +
                "===========================",
            MESSAGE_COUNT,
            sentCount.get(),
            receivedCount.get(),
            totalTime,
            consumeTime,
            String.format("%.2f", (double) totalProduceLatency / MESSAGE_COUNT),
            String.format("%.2f", (double) totalE2ELatency / MESSAGE_COUNT)
        );
    }
}
