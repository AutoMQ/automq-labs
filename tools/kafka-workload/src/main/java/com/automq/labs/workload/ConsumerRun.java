package com.automq.labs.workload;

import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.*;
import org.apache.kafka.common.header.Header;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;

final class ConsumerRun {
    private static final Duration TIMEOUT = Duration.ofSeconds(3);
    private final Options options;
    private final Events events;
    private final Control control;
    private final Consumer<byte[], byte[]> consumer;
    private final Map<TopicPartition, Long> next = new HashMap<>();
    private long messages, bytes, foreignMessages, foreignBytes, errors;
    private String errorCode;
    ConsumerRun(Options options, Events events, Control control, Consumer<byte[], byte[]> consumer) {
        this.options = options; this.events = events; this.control = control; this.consumer = consumer;
        control.onStop = consumer::wakeup;
    }
    Map<TopicPartition, Long> initialize() {
        List<TopicPartition> partitions = consumer.partitionsFor(options.required("topic"), TIMEOUT).stream()
            .map(p -> new TopicPartition(p.topic(), p.partition())).sorted(Comparator.comparingInt(TopicPartition::partition)).toList();
        if (partitions.isEmpty()) throw new IllegalStateException();
        consumer.assign(partitions);
        Map<TopicPartition, Long> starts;
        switch (options.required("start-position")) {
            case "current-end" -> starts = consumer.endOffsets(partitions, TIMEOUT);
            case "beginning" -> starts = consumer.beginningOffsets(partitions, TIMEOUT);
            case "committed" -> {
                Map<TopicPartition, OffsetAndMetadata> committed = consumer.committed(new HashSet<>(partitions), TIMEOUT);
                starts = new HashMap<>();
                for (TopicPartition p : partitions) {
                    OffsetAndMetadata offset = committed.get(p);
                    if (offset == null || offset.offset() < 0) throw new MissingCommittedOffset();
                    starts.put(p, offset.offset());
                }
            }
            default -> throw new IllegalArgumentException();
        }
        Map<TopicPartition, Long> beginnings = consumer.beginningOffsets(partitions, TIMEOUT);
        Map<TopicPartition, Long> ends = consumer.endOffsets(partitions, TIMEOUT);
        for (TopicPartition partition : partitions) {
            Long start = starts.get(partition);
            if (start == null || start < beginnings.get(partition) || start > ends.get(partition)) throw new InvalidStartOffset();
            consumer.seek(partition, start); next.put(partition, start);
        }
        // The ready frame is emitted only after every explicit seek, before the first poll.
        events.emit("ready", "ready", 0, 0, 0, Map.of("start_offsets", Events.offsets(next), "next_offsets", Events.offsets(next)));
        return Map.copyOf(next);
    }
    private void emit(String event, String state, Map<String, ?> extra) {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("next_offsets", Events.offsets(next)); detail.put("foreign_messages", foreignMessages);
        detail.put("foreign_payload_bytes", foreignBytes);
        detail.put("actual_read_messages", messages + foreignMessages); detail.put("actual_read_payload_bytes", bytes + foreignBytes);
        if (errorCode != null) detail.put("error_code", errorCode);
        detail.putAll(extra); events.emit(event, state, messages, bytes, errors, detail);
    }
    int run() {
        long lastProgress = System.nanoTime();
        try {
            initialize();
            while (!control.limit(options, events, messages, errors)) {
                ConsumerRecords<byte[], byte[]> records = consumer.poll(Duration.ofMillis(100));
                for (ConsumerRecord<byte[], byte[]> record : records) {
                    // If a limit stops a batch early, do not advance its unprocessed records.
                    if (control.limit(options, events, messages, errors)) break;
                    TopicPartition partition = new TopicPartition(record.topic(), record.partition());
                    next.put(partition, record.offset() + 1);
                    int length = record.value() == null ? 0 : record.value().length;
                    Header header = record.headers().lastHeader(ProducerRun.RUN_HEADER);
                    if (header != null && Arrays.equals(header.value(), options.required("run-id").getBytes(StandardCharsets.UTF_8))) {
                        messages++; bytes += length;
                    } else { foreignMessages++; foreignBytes += length; }
                }
                if (System.nanoTime() - lastProgress >= 1_000_000_000L) { emit("progress", "running", Map.of()); lastProgress = System.nanoTime(); }
            }
        } catch (RuntimeException failure) {
            if (!(failure instanceof org.apache.kafka.common.errors.WakeupException && control.stopped.get())) {
            errors++; errorCode = failure instanceof MissingCommittedOffset ? "committed_offset_missing"
                : failure instanceof InvalidStartOffset ? "start_offset_out_of_range" : Events.safeError(failure);
            control.stop("sdk_error");
            }
        } finally {
            emit("progress", "stopping", Map.of());
            try { consumer.close(Duration.ofSeconds(2)); }
            catch (RuntimeException failure) { errors++; errorCode = Events.safeError(failure); }
        }
        int code = errors > 0 ? 3 : 0;
        emit("final", code == 0 ? "stopped" : "failed", Map.of("exit_code", code, "stop_reason", control.reason, "unconfirmed_messages", 0));
        return code;
    }
    static final class MissingCommittedOffset extends RuntimeException { }
    static final class InvalidStartOffset extends RuntimeException { }
}
