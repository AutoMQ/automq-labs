package com.automq.labs.workload;

import com.fasterxml.jackson.databind.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.*;
import org.apache.kafka.common.errors.*;
import org.apache.kafka.common.serialization.ByteArraySerializer;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

class WorkloadTest {
    static final TopicPartition P0 = new TopicPartition("test", 0), P1 = new TopicPartition("test", 1);
    static final Node NODE = new Node(0, "localhost", 9092);
    final ByteArrayOutputStream output = new ByteArrayOutputStream();
    Options produce(String... extra) { return options("produce", extra); }
    Options consume(String... extra) { return options("consume", extra); }
    Options options(String role, String... extra) {
        List<String> args = new ArrayList<>(List.of(role, "--config", "unused", "--topic", "test", "--run-id", "run1"));
        if (role.equals("consume")) args.addAll(List.of("--group", "test-run1", "--start-position", "current-end"));
        args.addAll(Arrays.asList(extra)); return new Options(args.toArray(String[]::new));
    }
    List<PartitionInfo> partitions() {
        return List.of(new PartitionInfo("test", 0, NODE, new Node[]{NODE}, new Node[]{NODE}), new PartitionInfo("test", 1, NODE, new Node[]{NODE}, new Node[]{NODE}));
    }
    MockProducer<byte[], byte[]> producer(boolean automatic) {
        return new MockProducer<>(new Cluster("test", List.of(NODE), partitions(), Set.of(), Set.of()), automatic, new ByteArraySerializer(), new ByteArraySerializer());
    }
    MockConsumer<byte[], byte[]> consumer() {
        MockConsumer<byte[], byte[]> consumer = new MockConsumer<>(OffsetResetStrategy.NONE);
        consumer.updatePartitions("test", partitions());
        consumer.updateBeginningOffsets(Map.of(P0, 0L, P1, 0L));
        consumer.updateEndOffsets(Map.of(P0, 100L, P1, 200L));
        return consumer;
    }
    Events events(Options options) { return new Events(options, new PrintStream(output)); }
    List<JsonNode> frames() throws Exception {
        List<JsonNode> frames = new ArrayList<>();
        for (String line : output.toString(StandardCharsets.UTF_8).lines().toList()) frames.add(new ObjectMapper().readTree(line));
        return frames;
    }
    JsonNode last() throws Exception { List<JsonNode> frames = frames(); return frames.get(frames.size() - 1); }
    ConsumerRecord<byte[], byte[]> record(int partition, long offset, String run, int bytes) {
        ConsumerRecord<byte[], byte[]> record = new ConsumerRecord<>("test", partition, offset, null, new byte[bytes]);
        record.headers().add(ProducerRun.RUN_HEADER, run.getBytes(StandardCharsets.UTF_8)); return record;
    }
    @Test void producerCountsOnlyAcknowledgedDataAndCoversEveryPartition() throws Exception {
        Options options = produce("--max-messages", "6", "--rate-mibps", "1000", "--record-bytes", "100");
        MockProducer<byte[], byte[]> producer = producer(true);
        assertEquals(0, new ProducerRun(options, events(options), new Control(), producer).run());
        assertEquals(List.of(0, 1, 0, 1, 0, 1), producer.history().stream().map(ProducerRecord::partition).toList());
        assertEquals(6, last().get("messages").asLong()); assertEquals(600, last().get("payload_bytes").asLong());
        assertEquals(2, last().get("max_acked_offsets").get("test:0").asLong());
        assertEquals(0, last().get("no_acked_partitions").size());
        assertArrayEquals("run1".getBytes(StandardCharsets.UTF_8), producer.history().get(0).headers().lastHeader(ProducerRun.RUN_HEADER).value());
    }
    @Test void asynchronousAckFailureIsNotSuccessAndDoesNotExposeSecret() throws Exception {
        Options untilError = produce("--duration-seconds", "2", "--rate-mibps", "0.001");
        MockProducer<byte[], byte[]> delayed = producer(false);
        ExecutorService executor = Executors.newSingleThreadExecutor();
        try {
            Future<Integer> result = executor.submit(() -> new ProducerRun(untilError, events(untilError), new Control(), delayed).run());
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
            while (delayed.history().isEmpty() && System.nanoTime() < deadline) Thread.sleep(1);
            assertTrue(delayed.errorNext(new AuthenticationException("password=TOP_SECRET sasl.jaas.config=TOP_SECRET")));
            assertEquals(3, result.get(3, TimeUnit.SECONDS));
            assertEquals(0, last().get("messages").asLong()); assertEquals(1, last().get("errors").asLong());
            assertEquals("authentication_failed", last().get("error_code").asText()); assertFalse(output.toString().contains("TOP_SECRET"));
        } finally { executor.shutdownNow(); }
    }
    @Test void producerHasBoundedInflightAndMakesUnconfirmedVisible() throws Exception {
        Options options = produce("--duration-seconds", "1", "--rate-mibps", "1000");
        MockProducer<byte[], byte[]> producer = producer(false);
        assertEquals(4, new ProducerRun(options, events(options), new Control(), producer).run());
        assertEquals(ProducerRun.MAX_IN_FLIGHT, producer.history().size());
        assertEquals(ProducerRun.MAX_IN_FLIGHT, last().get("unconfirmed_messages").asLong());
        assertEquals(0, last().get("max_acked_offsets").size()); assertEquals(2, last().get("no_acked_partitions").size());
    }
    @Test void producerRateLimitUsesPayloadBytes() throws Exception {
        Options options = produce("--duration-seconds", "1", "--rate-mibps", "0.001", "--record-bytes", "1024");
        MockProducer<byte[], byte[]> producer = producer(true);
        assertEquals(0, new ProducerRun(options, events(options), new Control(), producer).run());
        assertTrue(producer.history().size() <= 2); assertTrue(last().get("elapsed_seconds").asDouble() >= 1);
    }
    @Test void consumerReadyIsAfterAllSeeksAndBeforeAnyNewRecord() throws Exception {
        Options options = consume("--max-messages", "2", "--duration-seconds", "2");
        MockConsumer<byte[], byte[]> consumer = consumer();
        consumer.schedulePollTask(() -> {
            assertEquals(Set.of(P0, P1), consumer.assignment());
            assertEquals(100, consumer.position(P0)); assertEquals(200, consumer.position(P1));
            assertTrue(output.toString().contains("\"event\":\"ready\""));
            consumer.addRecord(record(0, 100, "run1", 10)); consumer.addRecord(record(1, 200, "run1", 20));
        });
        assertEquals(0, new ConsumerRun(options, events(options), new Control(), consumer).run());
        assertEquals(100, frames().get(0).get("start_offsets").get("test:0").asLong());
        assertEquals(101, last().get("next_offsets").get("test:0").asLong());
        assertEquals(201, last().get("next_offsets").get("test:1").asLong()); assertEquals(30, last().get("payload_bytes").asLong());
    }
    @Test void inclusiveLastAckNeedsOneMoreExclusiveNextOffset() throws Exception {
        for (int count : List.of(1, 2)) {
            output.reset(); Options options = consume("--max-messages", Integer.toString(count), "--duration-seconds", "2");
            MockConsumer<byte[], byte[]> consumer = consumer(); consumer.updateEndOffsets(Map.of(P0, 108L, P1, 200L));
            consumer.schedulePollTask(() -> { consumer.addRecord(record(0, 108, "run1", 1)); consumer.addRecord(record(0, 109, "run1", 1)); });
            assertEquals(0, new ConsumerRun(options, events(options), new Control(), consumer).run());
            long exclusive = last().get("next_offsets").get("test:0").asLong();
            assertEquals(count == 2, exclusive >= 109L + 1);
        }
    }
    @Test void missingCommittedOffsetFailsWithoutReadyOrImplicitReset() throws Exception {
        Options options = consume("--duration-seconds", "1"); options.values.put("start-position", "committed");
        MockConsumer<byte[], byte[]> consumer = consumer();
        assertEquals(3, new ConsumerRun(options, events(options), new Control(), consumer).run());
        assertEquals("committed_offset_missing", last().get("error_code").asText());
        assertFalse(output.toString().contains("\"event\":\"ready\""));
    }
    @Test void existingCommittedOffsetsAreReadWithoutCommitOrReset() throws Exception {
        Options options = consume("--duration-seconds", "1", "--max-messages", "1"); options.values.put("start-position", "committed");
        MockConsumer<byte[], byte[]> consumer = new MockConsumer<>(OffsetResetStrategy.NONE) {
            @Override public Map<TopicPartition, OffsetAndMetadata> committed(Set<TopicPartition> partitions, Duration timeout) {
                return Map.of(P0, new OffsetAndMetadata(50), P1, new OffsetAndMetadata(60));
            }
            @Override public void commitSync(Map<TopicPartition, OffsetAndMetadata> offsets) { fail("Workload must never commit group offsets"); }
        };
        consumer.updatePartitions("test", partitions());
        consumer.updateBeginningOffsets(Map.of(P0, 0L, P1, 0L)); consumer.updateEndOffsets(Map.of(P0, 100L, P1, 200L));
        consumer.schedulePollTask(() -> {
            assertEquals(50, consumer.position(P0)); assertEquals(60, consumer.position(P1));
            consumer.addRecord(record(0, 50, "run1", 10));
        });
        assertEquals(0, new ConsumerRun(options, events(options), new Control(), consumer).run());
        assertEquals(50, frames().get(0).get("start_offsets").get("test:0").asLong());
        assertEquals(51, last().get("next_offsets").get("test:0").asLong());
    }
    @Test void emptyConsumerStopsWithZeroDataAndNoFalseProgress() throws Exception {
        Options options = consume("--duration-seconds", "1");
        assertEquals(0, new ConsumerRun(options, events(options), new Control(), consumer()).run());
        assertEquals(0, last().get("messages").asLong()); assertEquals(0, last().get("payload_bytes").asLong());
        assertEquals("duration", last().get("stop_reason").asText());
    }
    @Test void beginningIsExplicitAndForeignRecordsAreVisible() throws Exception {
        Options options = consume("--duration-seconds", "1", "--max-messages", "1"); options.values.put("start-position", "beginning");
        MockConsumer<byte[], byte[]> consumer = consumer();
        consumer.schedulePollTask(() -> { assertEquals(0, consumer.position(P0)); consumer.addRecord(record(0, 0, "old-run", 40)); consumer.addRecord(record(0, 1, "run1", 60)); });
        assertEquals(0, new ConsumerRun(options, events(options), new Control(), consumer).run());
        assertEquals(1, last().get("messages").asLong()); assertEquals(60, last().get("payload_bytes").asLong());
        assertEquals(1, last().get("foreign_messages").asLong()); assertEquals(100, last().get("actual_read_payload_bytes").asLong());
    }
    @Test void stoppingConsumerWakesPollAndClosesWithoutSdkFailure() throws Exception {
        Options options = consume("--duration-seconds", "2"); Control control = new Control();
        MockConsumer<byte[], byte[]> consumer = consumer(); consumer.schedulePollTask(() -> control.stop("signal"));
        assertEquals(0, new ConsumerRun(options, events(options), control, consumer).run());
        assertTrue(consumer.closed()); assertEquals("signal", last().get("stop_reason").asText());
    }
    @Test void invalidParametersAndConfigErrorsDoNotEchoSecrets(@TempDir Path dir) throws Exception {
        ByteArrayOutputStream error = new ByteArrayOutputStream();
        assertEquals(2, Workload.execute(new String[]{"produce", "--password", "TOP_SECRET"}, new PrintStream(output), new PrintStream(error)));
        assertFalse(error.toString().contains("TOP_SECRET"));
        for (String value : List.of("0", "-1", "NaN", "Infinity")) assertThrows(IllegalArgumentException.class, () -> produce("--rate-mibps", value));
        assertThrows(IllegalArgumentException.class, () -> produce("--record-bytes", "16777217"));
        assertThrows(IllegalArgumentException.class, () -> produce("--max-errors", "0"));
        Path properties = dir.resolve("secrets.properties"); Files.writeString(properties, "bootstrap.servers=TOP_SECRET_INVALID\nsasl.jaas.config=TOP_SECRET\n");
        assertEquals(3, Workload.execute(new String[]{"produce", "--config", properties.toString(), "--topic", "test", "--run-id", "run1"}, new PrintStream(output), new PrintStream(error)));
        assertFalse(output.toString().contains("TOP_SECRET")); assertFalse(error.toString().contains("TOP_SECRET"));
    }
    @Test void workloadOverridesUnsafeOffsetAndAckSettings() {
        Properties producer = new Properties(); producer.setProperty("acks", "0");
        Workload.producerProperties(produce(), producer); assertEquals("all", producer.getProperty("acks"));
        Properties consumer = new Properties(); consumer.setProperty("enable.auto.commit", "true"); consumer.setProperty("auto.offset.reset", "earliest");
        Workload.consumerProperties(consume(), consumer); assertEquals("false", consumer.getProperty("enable.auto.commit")); assertEquals("none", consumer.getProperty("auto.offset.reset"));
    }
}
