package com.automq.labs.workload;

import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;

final class ProducerRun {
    static final String RUN_HEADER = "workload-run-id";
    static final int MAX_IN_FLIGHT = 256;
    private final Options options;
    private final Events events;
    private final Control control;
    private final Producer<byte[], byte[]> producer;
    private final Semaphore slots = new Semaphore(MAX_IN_FLIGHT);
    private final Map<TopicPartition, Long> acked = new HashMap<>();
    private List<PartitionInfo> partitions = List.of();
    private long sent, messages, bytes, errors, completed;
    private String errorCode;
    ProducerRun(Options options, Events events, Control control, Producer<byte[], byte[]> producer) {
        this.options = options; this.events = events; this.control = control; this.producer = producer;
    }
    synchronized Map<String, Object> details(boolean terminal) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("sent_messages", sent);
        result.put("unconfirmed_messages", sent - completed);
        result.put("max_acked_offsets", Events.offsets(acked));
        if (errorCode != null) result.put("error_code", errorCode);
        if (terminal) result.put("no_acked_partitions", partitions.stream()
            .map(p -> new TopicPartition(p.topic(), p.partition())).filter(p -> !acked.containsKey(p)).map(Events::key).sorted().toList());
        return result;
    }
    private synchronized void emit(String event, String state, Map<String, ?> extra) {
        Map<String, Object> detail = details(event.equals("final")); detail.putAll(extra);
        events.emit(event, state, messages, bytes, errors, detail);
    }
    private synchronized void ack(RecordMetadata metadata, Exception error, int length) {
        completed++;
        if (error != null || metadata == null || metadata.offset() < 0) {
            errors++; errorCode = error == null ? "ack_offset_unavailable" : Events.safeError(error);
        } else {
            messages++; bytes += length;
            acked.merge(new TopicPartition(metadata.topic(), metadata.partition()), metadata.offset(), Math::max);
        }
        slots.release();
    }
    int run() {
        long lastProgress = System.nanoTime();
        try {
            partitions = producer.partitionsFor(options.required("topic")).stream().sorted(Comparator.comparingInt(PartitionInfo::partition)).toList();
            if (partitions.isEmpty()) throw new IllegalStateException();
            byte[] payload = new byte[(int) options.positive("record-bytes", 1024, 16 * 1024 * 1024)];
            new Random(1).nextBytes(payload);
            byte[] runId = options.required("run-id").getBytes(StandardCharsets.UTF_8);
            long firstSend = System.nanoTime();
            while (true) {
                long attempts, failures;
                synchronized (this) { attempts = sent; failures = errors; }
                if (control.limit(options, events, attempts, failures)) break;
                long now = System.nanoTime();
                if (now - lastProgress >= 1_000_000_000L) { emit("progress", "running", Map.of()); lastProgress = now; }
                // Account for payload bytes, without accumulating tokens during SDK backpressure.
                double due = attempts * (double) payload.length / (options.rate() * 1048576.0);
                double wait = due - (now - firstSend) / 1e9;
                if (wait > 0) { Thread.sleep(Math.min(50L, Math.max(1L, (long) (wait * 1000)))); continue; }
                if (!slots.tryAcquire(50, TimeUnit.MILLISECONDS)) continue;
                int partition = partitions.get((int) (attempts % partitions.size())).partition();
                ProducerRecord<byte[], byte[]> record = new ProducerRecord<>(options.required("topic"), partition, null, payload);
                record.headers().add(RUN_HEADER, runId);
                synchronized (this) { sent++; }
                try { producer.send(record, (metadata, error) -> ack(metadata, error, payload.length)); }
                catch (RuntimeException failure) { ack(null, failure, payload.length); }
                // Prevent a delayed producer from bursting an unbounded accumulated allowance.
                if ((System.nanoTime() - firstSend) / 1e9 - due > 0.1)
                    firstSend = System.nanoTime() - (long) (due * 1e9);
            }
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt(); control.stop("interrupted");
        } catch (RuntimeException failure) {
            synchronized (this) { errors++; errorCode = Events.safeError(failure); }
            control.stop("sdk_error");
        } finally {
            emit("progress", "stopping", Map.of());
            try { producer.close(Duration.ofSeconds(2)); }
            catch (RuntimeException failure) { synchronized (this) { errors++; errorCode = Events.safeError(failure); } }
        }
        int code;
        synchronized (this) { code = sent > completed ? 4 : errors > 0 ? 3 : 0; }
        emit("final", code == 0 ? "stopped" : "failed", Map.of("exit_code", code, "stop_reason", control.reason));
        return code;
    }
}
