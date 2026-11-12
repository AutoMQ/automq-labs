package com.automq.labs.workload;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.PrintStream;
import java.time.Instant;
import java.util.*;

final class Events {
    private final ObjectMapper mapper = new ObjectMapper();
    private final PrintStream out;
    private final Options options;
    private final long started = System.nanoTime();
    private long seq, previousBytes, previousTime = started;
    Events(Options options, PrintStream out) { this.options = options; this.out = out; }
    double elapsed() { return (System.nanoTime() - started) / 1e9; }
    synchronized void emit(String event, String state, long messages, long bytes, long errors, Map<String, ?> extra) {
        long now = System.nanoTime();
        Map<String, Object> frame = new LinkedHashMap<>();
        frame.put("schema_version", 1); frame.put("event", event); frame.put("role", options.role);
        frame.put("run_id", options.get("run-id", "")); frame.put("sample_seq", ++seq);
        frame.put("sample_time", Instant.now().toString()); frame.put("elapsed_seconds", elapsed());
        frame.put("messages", messages); frame.put("payload_bytes", bytes); frame.put("errors", errors);
        frame.put("rate_mibps", (bytes - previousBytes) / 1048576.0 / Math.max((now - previousTime) / 1e9, 1e-9));
        frame.put("state", state); frame.putAll(extra);
        try { out.println(mapper.writeValueAsString(frame)); out.flush(); }
        catch (java.io.IOException impossible) { throw new IllegalStateException("JSON encoding failed"); }
        previousBytes = bytes; previousTime = now;
    }
    static String key(org.apache.kafka.common.TopicPartition p) { return p.topic() + ":" + p.partition(); }
    static Map<String, Long> offsets(Map<org.apache.kafka.common.TopicPartition, Long> offsets) {
        Map<String, Long> result = new TreeMap<>(); offsets.forEach((p, offset) -> result.put(key(p), offset)); return result;
    }
    static String safeError(Throwable error) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause instanceof org.apache.kafka.common.errors.AuthenticationException) return "authentication_failed";
            if (cause instanceof org.apache.kafka.common.errors.AuthorizationException) return "authorization_failed";
            if (cause instanceof org.apache.kafka.common.errors.TimeoutException || cause instanceof java.util.concurrent.TimeoutException) return "operation_timed_out";
        }
        return "operation_failed";
    }
}
