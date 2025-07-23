package com.automq.examples;

import java.util.Properties;
import java.util.concurrent.Future;
import lombok.extern.slf4j.Slf4j;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * Kafka regular message producer example
 */
@Slf4j
public class SimpleProducer {


    public static void main(String[] args) {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
        String topicName = AutoMQExampleConstants.TOPIC_NAME;

        // Create producer configuration
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());

        // Set acknowledgment to all
        props.put(ProducerConfig.ACKS_CONFIG, AutoMQExampleConstants.ACKS_CONFIG);
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
            log.info("Kafka producer created successfully, starting to send messages...");

            // Send 10 messages
            for (int i = 0; i < 10; i++) {
                String key = "key-" + i;
                String value = "message-" + i;

                // Create message record
                ProducerRecord<String, String> record = new ProducerRecord<>(topicName, key, value);

                // Send message
                Future<RecordMetadata> future = producer.send(record, (metadata, exception) -> {
                    if (exception == null) {
                        log.info("Message sent successfully: topic={}, partition={}, offset={}",
                            metadata.topic(), metadata.partition(), metadata.offset());
                    } else {
                        log.error("Failed to send message", exception);
                    }
                });
            }

            // Ensure all messages are sent
            producer.flush();
            log.info("All messages sent successfully");
        } catch (Exception e) {
            log.error("Error occurred while sending messages", e);
            e.printStackTrace();
        }
    }
}