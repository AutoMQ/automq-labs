package com.automq.examples;

import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.KafkaException;
import org.apache.kafka.common.errors.AuthorizationException;
import org.apache.kafka.common.errors.OutOfOrderSequenceException;
import org.apache.kafka.common.errors.ProducerFencedException;
import org.apache.kafka.common.serialization.StringSerializer;

import java.util.Properties;
import java.util.UUID;

/**
 * Kafka transactional message producer example
 */
@Slf4j
public class TransactionalProducer {

    public static void main(String[] args) {

        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
        String topicName = AutoMQExampleConstants.TRANSACTIONAL_TOPIC_NAME;

        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        
        // Set transaction ID, must be unique
        String transactionalId = "transactional-producer-" + UUID.randomUUID();
        props.put(ProducerConfig.TRANSACTIONAL_ID_CONFIG, transactionalId);
        
        // Set acknowledgment to all
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
        // Set retry count
        props.put(ProducerConfig.RETRIES_CONFIG, AutoMQExampleConstants.RETRIES_CONFIG);
        // Enable idempotence
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, AutoMQExampleConstants.ENABLE_IDEMPOTENCE_CONFIG);

        // Set metadata max age
        props.put(ProducerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        // Set batch size
        props.put(ProducerConfig.BATCH_SIZE_CONFIG, AutoMQExampleConstants.BATCH_SIZE);
        // Set batch delay
        props.put(ProducerConfig.LINGER_MS_CONFIG, AutoMQExampleConstants.LINGER_MS);
        // Set buffer memory size
        props.put(ProducerConfig.BUFFER_MEMORY_CONFIG, AutoMQExampleConstants.BUFFER_MEMORY);
        // Set max request size
        props.put(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, AutoMQExampleConstants.MAX_REQUEST_SIZE);

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            // Initialize transaction
            producer.initTransactions();
            log.info("Transaction initialized successfully, starting to send transactional messages...");

            try {
                // Begin transaction
                producer.beginTransaction();
                log.info("Transaction started");

                // Send multiple messages in one transaction
                for (int i = 0; i < 5; i++) {
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

            } catch (ProducerFencedException | OutOfOrderSequenceException | AuthorizationException e) {
                // These exceptions indicate the transaction cannot continue, producer must be closed
                log.error("Critical error, transaction cannot continue: ", e);
                producer.close();
            } catch (KafkaException e) {
                // Other Kafka-related exceptions, can try to abort the transaction
                log.error("Kafka exception, attempting to abort transaction: ", e);
                producer.abortTransaction();
            }

            log.info("Transactional message sending completed");
        } catch (Exception e) {
            log.error("Error occurred while sending transactional messages: ", e);
            e.printStackTrace();
        }
    }
}