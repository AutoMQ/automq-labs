package com.automq.examples;

import java.util.Properties;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * Kafka regular message producer example
 */
@Slf4j
public class SimpleProducer {

    public static void main(String[] args) {
        String topicName = AutoMQExampleConstants.TOPIC_NAME;
        Properties props = createProducerConfig();

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            sendMessages(producer, topicName);
            log.info("All messages sent successfully");
        } catch (Exception e) {
            log.error("Error occurred while sending messages", e);
        }

    }

    private static Properties createProducerConfig() {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, AutoMQExampleConstants.BATCH_SIZE);
        props.put(ProducerConfig.LINGER_MS_CONFIG, AutoMQExampleConstants.LINGER_MS);
        props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, AutoMQExampleConstants.BUFFER_MEMORY);
        props.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, AutoMQExampleConstants.MAX_REQUEST_SIZE);

        return props;
    }

    private static void sendMessages(KafkaProducer<String, String> producer, String topicName) {
        log.info("Kafka producer created successfully, starting to send messages...");

        //  Implementation of related business logic
        for (int i = 0; i < 20; i++) {
            String orderId = "order-" + System.currentTimeMillis();
            String orderJson = "{\"orderId\":\"" + orderId + "\"}";
            ProducerRecord<String, String> orderRecord = new ProducerRecord<>(topicName, orderId, orderJson);
            producer.send(orderRecord, createCallback("Order"));
        }

    }

    private static Callback createCallback(String messageType) {
        return (metadata, exception) -> {
            if (exception == null) {
                log.info("{} message sent successfully: topic={}, partition={}, offset={}",
                    messageType, metadata.topic(), metadata.partition(), metadata.offset());
            } else {
                log.error("Failed to send {} message", messageType, exception);
            }
        };
    }
}