package com.automq.examples;

import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import java.util.UUID;
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
 * Transactional message example that demonstrates both transactional producer and consumer with performance metrics
 */
@Slf4j
public class TransactionalMessageExample {

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
    private static final String topicName = AutoMQExampleConstants.TRANSACTIONAL_TOPIC_NAME;
    private static final String groupId = AutoMQExampleConstants.TRANSACTIONAL_CONSUMER_GROUP_ID;

    public static void main(String[] args) {
        log.info("Starting Transactional Message Example...");
        log.info("Will send and receive {} transactional messages", MESSAGE_COUNT);

        CountDownLatch consumerReady = new CountDownLatch(1);
        CountDownLatch allMessagesReceived = new CountDownLatch(1);

        ExecutorService executor = Executors.newFixedThreadPool(2);

        try {
            // Start consumer in a separate thread
            executor.submit(() -> {
                runTransactionalConsumer(consumerReady, allMessagesReceived);
            });

            // Wait for consumer to be ready
            consumerReady.await();
            Thread.sleep(2000); // Give consumer time to subscribe

            // Start producer
            executor.submit(() -> {
                runTransactionalProducer(topicName);
            });

            // Wait for all messages to be received
            allMessagesReceived.await();

            // Print performance metrics
            printPerformanceMetrics();

        } catch (Exception e) {
            log.error("Error occurred during transactional message example", e);
        } finally {
            executor.shutdown();
        }

        log.info("Transactional Message Example completed.");
    }

    private static void runTransactionalProducer(String topicName) {
        Properties props = createTransactionalProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            // Initialize transactions
            producer.initTransactions();

            log.info("Transactional producer started, sending {} messages...", MESSAGE_COUNT);
            startTime = System.currentTimeMillis();

            // Begin transaction
            producer.beginTransaction();

            try {
                for (int i = 0; i < MESSAGE_COUNT; i++) {
                    String messageId = "txn-msg-" + i;
                    long sendTime = System.currentTimeMillis();
                    String messageValue = "{\"id\":\"" + messageId + "\",\"timestamp\":" + sendTime + ",\"content\":\"Hello AutoMQ Transactional " + i + "\"}";

                    ProducerRecord<String, String> record = new ProducerRecord<>(topicName, messageId, messageValue);

                    producer.send(record, createTransactionalProducerCallback(i, sendTime));
                }

                producer.flush(); // Ensure all messages are sent

                // Commit transaction
                producer.commitTransaction();
                log.info("Transaction committed successfully. All {} messages sent", MESSAGE_COUNT);

            } catch (Exception e) {
                log.error("Error in transaction, aborting...", e);
                producer.abortTransaction();
                throw e;
            }

        } catch (Exception e) {
            log.error("Error occurred while sending transactional messages", e);
        }
    }

    private static void runTransactionalConsumer(CountDownLatch consumerReady,
        CountDownLatch allMessagesReceived) {
        Properties props = createTransactionalConsumerConfig();

        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(Collections.singletonList(topicName));
            log.info("Transactional consumer subscribed to topic: {}", topicName);
            consumerReady.countDown();

            while (receivedCount.get() < MESSAGE_COUNT) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(1000));

                for (ConsumerRecord<String, String> record : records) {
                    int currentCount = receivedCount.incrementAndGet();
                    long e2eLatency = System.currentTimeMillis() - record.timestamp();

                    if (currentCount == 1) {
                        firstMessageTime = System.currentTimeMillis();
                    }
                    synchronized (e2eLatencyLock) {
                        totalE2ELatency += e2eLatency;
                    }

                    log.info("Received transactional message {}/{}: key={}, partition={}, offset={}, e2eLatency={}ms",
                        currentCount, MESSAGE_COUNT, record.key(), record.partition(), record.offset(), e2eLatency);

                    if (currentCount == MESSAGE_COUNT) {
                        lastMessageTime = System.currentTimeMillis();
                        endTime = System.currentTimeMillis();
                        allMessagesReceived.countDown();
                        break;
                    }
                }

                // Commit offsets manually for transactional consumer
                consumer.commitSync();
            }

        } catch (Exception e) {
            log.error("Error occurred while consuming transactional messages", e);
        }
    }

    private static Properties createTransactionalProducerConfig() {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
        props.put(ProducerConfig.RETRIES_CONFIG, AutoMQExampleConstants.RETRIES_CONFIG);
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, AutoMQExampleConstants.BATCH_SIZE);
        props.put(ProducerConfig.LINGER_MS_CONFIG, AutoMQExampleConstants.LINGER_MS);
        props.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, AutoMQExampleConstants.MAX_REQUEST_SIZE);
        String transactionalId = "transactional-producer-" + UUID.randomUUID();
        props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, transactionalId);

        return props;
    }

    private static Properties createTransactionalConsumerConfig() {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.ISOLATION_LEVEL_CONFIG, AutoMQExampleConstants.ISOLATION_LEVEL);
        props.put(ConsumerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ConsumerConfig.MAX_PARTITION_FETCH_BYTES_CONFIG, AutoMQExampleConstants.MAX_PARTITION_FETCH_BYTES);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, AutoMQExampleConstants.AUTO_OFFSET_RESET);
        return props;
    }

    private static Callback createTransactionalProducerCallback(int messageIndex, long sendTime) {
        return (metadata, exception) -> {
            if (exception == null) {
                long ackTime = System.currentTimeMillis();
                long latency = ackTime - sendTime;

                synchronized (latencyLock) {
                    totalProduceLatency += latency;
                }

                int currentCount = sentCount.incrementAndGet();
                log.info("Transactional message {}/{} sent successfully: topic={}, partition={}, offset={}, produce latency={}ms",
                    currentCount, MESSAGE_COUNT, metadata.topic(), metadata.partition(), metadata.offset(), latency);
            } else {
                log.error("Failed to send transactional message {}", messageIndex, exception);
            }
        };
    }

    private static void printPerformanceMetrics() {
        long totalTime = endTime - startTime;
        long consumeTime = lastMessageTime - firstMessageTime;

        log.info("=== Transactional Performance Metrics ===\n" +
                "Total Messages: {}\n" +
                "Messages Sent: {}\n" +
                "Messages Received: {}\n" +
                "Total Time: {} ms\n" +
                "Consume Time: {} ms\n" +
                "Average Produce Latency: {} ms\n" +
                "Average End-to-End Latency: {} ms\n" +
                "=========================================",
            MESSAGE_COUNT,
            sentCount.get(),
            receivedCount.get(),
            totalTime,
            consumeTime,
            (double) totalProduceLatency / MESSAGE_COUNT,
            (double) totalE2ELatency / MESSAGE_COUNT
        );
    }
}
