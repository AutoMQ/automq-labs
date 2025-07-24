package com.automq.examples;

import java.util.Properties;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * Kafka transactional message producer example
 */
@Slf4j
public class TransactionalProducer {

    public static void main(String[] args) {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
        String topicName = AutoMQExampleConstants.TRANSACTIONAL_TOPIC_NAME;

        Properties props = createTransactionalProducerConfig(bootstrapServers);

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            executeTransactions(producer, topicName);
            log.info("Transactional message sending completed");
        } catch (Exception e) {
            log.error("Error occurred while sending transactional messages: ", e);
        }
    }

    private static Properties createTransactionalProducerConfig(String bootstrapServers) {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
        props.put(ProducerConfig.RETRIES_CONFIG, AutoMQExampleConstants.RETRIES_CONFIG);
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, AutoMQExampleConstants.ENABLE_IDEMPOTENCE_CONFIG);
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, AutoMQExampleConstants.BATCH_SIZE);
        props.put(ProducerConfig.LINGER_MS_CONFIG, AutoMQExampleConstants.LINGER_MS);
        props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, AutoMQExampleConstants.BUFFER_MEMORY);
        props.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, AutoMQExampleConstants.MAX_REQUEST_SIZE);
        String transactionalId = "transactional-producer-" + UUID.randomUUID();
        props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, transactionalId);
        return props;
    }

    private static void executeTransactions(KafkaProducer<String, String> producer, String topicName) {
        // Initialize transaction
        producer.initTransactions();
        log.info("Transaction initialized successfully, starting to send transactional messages...");

        try {
            // Begin transaction
            producer.beginTransaction();
            log.info("Transaction started");

            // Send multiple messages in one transaction
            for (int i = 0; i < 50; i++) {
                String key = "tx-key-" + i;
                String value = "tx-message-" + i;

                // Create message record
                ProducerRecord<String, String> record = new ProducerRecord<>(topicName, key, value);

                // Send message
                producer.send(record, (metadata, exception) -> {
                    if (exception == null) {
                        log.info("Transactional message sent successfully: topic={}, partition={}, offset={}",
                            metadata.topic(), metadata.partition(), metadata.offset());
                    } else {
                        log.error("Failed to send transactional message: " + exception.getMessage());
                    }
                });
            }

            // Commit transaction
            producer.commitTransaction();
            log.info("Transaction committed");

            // Demonstrate transaction rollback
            // Start a new transaction
            producer.beginTransaction();
            log.info("Starting second transaction (will be rolled back)");

            // Send some messages
            for (int i = 5; i < 10; i++) {
                String key = "tx-key-" + i;
                String value = "tx-message-" + i + " (will be rolled back)";

                ProducerRecord<String, String> record = new ProducerRecord<>(topicName, key, value);
                producer.send(record);
            }

            // Abort transaction
            producer.abortTransaction();
            log.info("Second transaction rolled back, these messages won't be visible to consumers");

        } catch (Exception e) {
            // Other Kafka-related exceptions, can try to abort the transaction
            log.error("Kafka exception", e);
            producer.abortTransaction();
        }

        log.info("Transactional message sending completed");
    }

}