package com.automq.labs.workload;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.admin.*;
import org.apache.kafka.common.*;
import org.apache.kafka.common.errors.TopicExistsException;
import org.apache.kafka.common.internals.KafkaFutureImpl;
import org.junit.jupiter.api.Test;
import java.io.*;
import java.lang.reflect.Proxy;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;

class TopicTest {
    static final class CreateResult extends CreateTopicsResult {
        private final KafkaFuture<Void> result;
        CreateResult(boolean exists) {
            super(Map.of());
            KafkaFutureImpl<Void> future = new KafkaFutureImpl<>();
            if (exists) future.completeExceptionally(new TopicExistsException("already exists")); else future.complete(null);
            result = future;
        }
        @Override public KafkaFuture<Void> all() { return result; }
    }
    static final class DescribeResult extends DescribeTopicsResult {
        DescribeResult(int count) { super(Map.of("test", KafkaFuture.completedFuture(description(count)))); }
        static TopicDescription description(int count) {
            List<TopicPartitionInfo> partitions = new ArrayList<>();
            for (int i = 0; i < count; i++) partitions.add(new TopicPartitionInfo(i, Node.noNode(), List.of(), List.of()));
            return new TopicDescription("test", false, partitions);
        }
    }
    @Test void existingTopicIsOnlyDescribedAndMismatchFailsWithoutAlterOrDelete() throws Exception {
        List<String> calls = new ArrayList<>();
        Admin admin = (Admin) Proxy.newProxyInstance(Admin.class.getClassLoader(), new Class[]{Admin.class}, (proxy, method, args) -> {
            calls.add(method.getName());
            if (method.getName().equals("createTopics")) return new CreateResult(true);
            if (method.getName().equals("describeTopics")) return new DescribeResult(3);
            throw new AssertionError("Unexpected operation: " + method.getName());
        });
        Options options = new Options("topic", "create", "--config", "unused", "--topic", "test", "--partitions", "9");
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        assertEquals(3, Workload.topic(options, new Events(options, new PrintStream(output)), admin));
        assertEquals(List.of("createTopics", "describeTopics"), calls);
        var frame = new ObjectMapper().readTree(output.toString());
        assertFalse(frame.get("created").asBoolean()); assertEquals(3, frame.get("partitions").asInt());
        assertEquals("partition_count_mismatch", frame.get("stop_reason").asText());
    }
    @Test void describeNeverCallsCreate() throws Exception {
        Admin admin = (Admin) Proxy.newProxyInstance(Admin.class.getClassLoader(), new Class[]{Admin.class}, (proxy, method, args) -> {
            assertEquals("describeTopics", method.getName()); return new DescribeResult(3);
        });
        Options options = new Options("topic", "describe", "--config", "unused", "--topic", "test");
        assertEquals(0, Workload.topic(options, new Events(options, new PrintStream(new ByteArrayOutputStream())), admin));
    }
}
