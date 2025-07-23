package com.automq.examples;

import java.time.Duration;
import java.util.Collections;
import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.errors.WakeupException;
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * Kafka regular message consumer example
 */
@Slf4j
public class SimpleConsumer {

    public static void main(String[] args) {

        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
        String topicName = AutoMQExampleConstants.TOPIC_NAME;
        String groupId = AutoMQExampleConstants.CONSUMER_GROUP_ID;

        // Create consumer configuration
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());

        props.put(ConsumerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ConsumerConfig.MAX_PARTITION_FETCH_BYTES_CONFIG, AutoMQExampleConstants.MAX_PARTITION_FETCH_BYTES);

        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, AutoMQExampleConstants.AUTO_OFFSET_RESET);

        // Create consumer
        final KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props);

        // Latch for graceful shutdown
        final CountDownLatch latch = new CountDownLatch(1);

        // Register shutdown hook
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log.info("Shutting down consumer...");
            consumer.wakeup();
            try {
                latch.await();
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }));

        try {
            // Subscribe to topic
            consumer.subscribe(Collections.singletonList(topicName));
            log.info("Subscribed to topic: {}", topicName);
            log.info("Starting to consume messages, press Ctrl+C to exit...");

            // Continuously consume messages
            while (true) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
                for (ConsumerRecord<String, String> record : records) {
                    log.info("Received message: topic={}, partition={}, offset={}, key={}, value={}",
                        record.topic(), record.partition(), record.offset(), record.key(), record.value());
                }
            }
        } catch (WakeupException e) {
            // Ignore, this is triggered by the shutdown hook calling wakeup()
            log.info("Received shutdown signal");
        } catch (Exception e) {
            log.error("Error occurred while consuming messages", e);
            e.printStackTrace();
        } finally {
            // Close consumer
            consumer.close();
            latch.countDown();
            log.info("Consumer closed");
        }
    }
}