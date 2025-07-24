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
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * Kafka transactional message consumer example
 */
@Slf4j
public class TransactionalConsumer {

    public static void main(String[] args) {
        String bootstrapServers = AutoMQExampleConstants.BOOTSTRAP_SERVERS;
        String topicName = AutoMQExampleConstants.TRANSACTIONAL_TOPIC_NAME;
        String group = AutoMQExampleConstants.TRANSACTIONAL_CONSUMER_GROUP_ID;

        Properties props = createConsumerConfig(bootstrapServers, group);
        KafkaConsumer<String, String> consumer = createConsumer(props);

        try {
            consumeMessages(consumer, topicName);
        } catch (Exception e) {
            log.error("Error occurred while consuming messages: ", e);
            e.printStackTrace();
        } finally {
            if (consumer != null) {
                consumer.close();
            }
        }
    }

    private static Properties createConsumerConfig(String bootstrapServers, String group) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, group);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.ISOLATION_LEVEL_CONFIG, AutoMQExampleConstants.ISOLATION_LEVEL);
        props.put(ConsumerConfig.METADATA_MAX_AGE_CONFIG, AutoMQExampleConstants.METADATA_MAX_AGE_MS);
        props.put(ConsumerConfig.MAX_PARTITION_FETCH_BYTES_CONFIG, AutoMQExampleConstants.MAX_PARTITION_FETCH_BYTES);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, AutoMQExampleConstants.AUTO_OFFSET_RESET);
        return props;
    }

    private static KafkaConsumer<String, String> createConsumer(Properties props) {
        return new KafkaConsumer<>(props);
    }

    private static void consumeMessages(KafkaConsumer<String, String> consumer, String topicName) {

        final CountDownLatch latch = new CountDownLatch(1);
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            log.info("Shutting down consumer...");
            consumer.wakeup();
            try {
                latch.await();
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }));

        consumer.subscribe(Collections.singletonList(topicName));
        log.info("Subscribed to topic: {}", topicName);
        log.info("Starting to consume transactional messages, will only receive committed transaction messages, press Ctrl+C to exit...");

        while (true) {
            ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(100));
            for (ConsumerRecord<String, String> record : records) {
                log.info("Received transactional message: topic={}, partition={}, offset={}, key={}, value={}",
                    record.topic(), record.partition(), record.offset(), record.key(), record.value());
            }
        }
    }

}