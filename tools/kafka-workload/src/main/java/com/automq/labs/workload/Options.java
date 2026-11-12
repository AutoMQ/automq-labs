package com.automq.labs.workload;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;

final class Options {
    final String role, operation;
    final Map<String, String> values = new HashMap<>();
    Options(String... args) {
        if (args.length == 0 || !Set.of("topic", "produce", "consume").contains(args[0])) throw new IllegalArgumentException();
        role = args[0];
        int first = 1;
        if (role.equals("topic")) {
            if (args.length < 2 || !Set.of("create", "describe").contains(args[1])) throw new IllegalArgumentException();
            operation = args[1]; first = 2;
        } else operation = role;
        Set<String> allowed = new HashSet<>(Set.of("config", "topic"));
        if (role.equals("topic") && operation.equals("create")) allowed.add("partitions");
        if (!role.equals("topic")) allowed.addAll(Set.of("run-id", "duration-seconds", "max-messages", "max-errors"));
        if (role.equals("produce")) allowed.addAll(Set.of("rate-mibps", "record-bytes", "compression", "partition-mode"));
        if (role.equals("consume")) allowed.addAll(Set.of("group", "start-position"));
        for (int i = first; i < args.length; i += 2) {
            if (!args[i].startsWith("--") || i + 1 == args.length) throw new IllegalArgumentException();
            String key = args[i].substring(2);
            if (!allowed.contains(key) || values.putIfAbsent(key, args[i + 1]) != null) throw new IllegalArgumentException();
        }
        required("config");
        if (!required("topic").matches("[A-Za-z0-9._-]{1,249}") || Set.of(".", "..").contains(get("topic", ""))) throw new IllegalArgumentException();
        if (role.equals("topic")) { if (operation.equals("create")) positive("partitions", 0, 100000); return; }
        if (!required("run-id").matches("[A-Za-z0-9_-]{1,64}")) throw new IllegalArgumentException();
        positive("duration-seconds", Long.MAX_VALUE, Long.MAX_VALUE);
        positive("max-messages", Long.MAX_VALUE, Long.MAX_VALUE);
        positive("max-errors", 1, Long.MAX_VALUE);
        if (role.equals("produce")) {
            positive("record-bytes", 1024, 16 * 1024 * 1024);
            double rate = rate();
            if (!Double.isFinite(rate) || rate <= 0 || rate > 1048576) throw new IllegalArgumentException();
            if (!Set.of("none", "gzip", "snappy", "lz4", "zstd").contains(get("compression", "none"))) throw new IllegalArgumentException();
            if (!get("partition-mode", "round-robin").equals("round-robin")) throw new IllegalArgumentException();
        } else {
            if (!required("group").matches("[A-Za-z0-9._-]{1,249}")) throw new IllegalArgumentException();
            if (!Set.of("current-end", "beginning", "committed").contains(required("start-position"))) throw new IllegalArgumentException();
        }
    }
    String get(String key, String fallback) { return values.getOrDefault(key, fallback); }
    String required(String key) { String value = values.get(key); if (value == null || value.isBlank()) throw new IllegalArgumentException(); return value; }
    long positive(String key, long fallback, long max) {
        long value = Long.parseLong(get(key, Long.toString(fallback)));
        if (value <= 0 || value > max) throw new IllegalArgumentException();
        return value;
    }
    double rate() { return Double.parseDouble(get("rate-mibps", "1")); }
    Properties properties() throws IOException {
        Properties properties = new Properties();
        try (InputStream in = Files.newInputStream(Path.of(required("config")))) { properties.load(in); }
        if (properties.getProperty("bootstrap.servers", "").isBlank()) throw new IllegalArgumentException();
        // Limit every SDK blocking operation; never log Properties or exception messages.
        properties.setProperty("default.api.timeout.ms", "3000");
        properties.setProperty("request.timeout.ms", "3000");
        properties.setProperty("max.block.ms", "3000");
        return properties;
    }
}
