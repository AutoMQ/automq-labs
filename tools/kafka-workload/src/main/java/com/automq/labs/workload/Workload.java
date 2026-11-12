package com.automq.labs.workload;

import org.apache.kafka.clients.admin.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.errors.TopicExistsException;
import org.apache.kafka.common.serialization.*;
import java.io.PrintStream;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;

public final class Workload {
    private Workload() { }
    public static void main(String[] args) { System.exit(execute(args, System.out, System.err)); }
    static int execute(String[] args, PrintStream out, PrintStream err) {
        if (args.length == 1 && (args[0].equals("--help") || args[0].equals("help"))) { out.println(HELP); return 0; }
        Options options;
        try { options = new Options(args); }
        catch (RuntimeException failure) { err.println("invalid_arguments: use --help; option values are not echoed."); return 2; }
        Events events = new Events(options, out);
        Control control = new Control();
        Thread hook = control.hook();
        Runtime.getRuntime().addShutdownHook(hook);
        try {
            Properties properties = options.properties();
            if (options.role.equals("topic")) return topic(options, events, properties);
            // Explicitly require an existing topic before allowing a workload to start.
            Admin checkAdmin = Admin.create(properties);
            try { describe(checkAdmin, options.required("topic")); }
            finally { checkAdmin.close(Duration.ofSeconds(1)); }
            if (options.role.equals("produce")) {
                producerProperties(options, properties);
                return new ProducerRun(options, events, control, new KafkaProducer<>(properties)).run();
            }
            consumerProperties(options, properties);
            return new ConsumerRun(options, events, control, new KafkaConsumer<>(properties)).run();
        } catch (Exception failure) {
            String error = failure instanceof java.io.IOException ? "config_file_unreadable" : Events.safeError(failure);
            err.println(error + ": check the configuration file, permissions and Kafka connectivity.");
            events.emit("final", "failed", 0, 0, 1, Map.of("exit_code", 3, "stop_reason", "setup_error", "unconfirmed_messages", 0, "error_code", error));
            return 3;
        } finally {
            control.done.countDown();
            try { Runtime.getRuntime().removeShutdownHook(hook); } catch (IllegalStateException shutdownInProgress) { /* Signal owns the hook. */ }
        }
    }
    static void producerProperties(Options options, Properties properties) {
        properties.setProperty(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        properties.setProperty(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, ByteArraySerializer.class.getName());
        properties.setProperty(ProducerConfig.ACKS_CONFIG, "all");
        properties.setProperty(ProducerConfig.COMPRESSION_TYPE_CONFIG, options.get("compression", "none"));
        properties.setProperty(ProducerConfig.BUFFER_MEMORY_CONFIG, "33554432");
        properties.setProperty(ProducerConfig.MAX_REQUEST_SIZE_CONFIG, Long.toString(options.positive("record-bytes", 1024, 16 * 1024 * 1024) + 4096));
        properties.setProperty(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "5000");
        properties.setProperty(ProducerConfig.LINGER_MS_CONFIG, "0");
        properties.setProperty(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, "5");
    }
    static void consumerProperties(Options options, Properties properties) {
        properties.setProperty(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        properties.setProperty(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, ByteArrayDeserializer.class.getName());
        properties.setProperty(ConsumerConfig.GROUP_ID_CONFIG, options.required("group"));
        properties.setProperty(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        properties.setProperty(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "none");
        properties.setProperty(ConsumerConfig.ALLOW_AUTO_CREATE_TOPICS_CONFIG, "false");
    }
    static TopicDescription describe(Admin admin, String topic) throws Exception {
        return admin.describeTopics(List.of(topic), new DescribeTopicsOptions().timeoutMs(3000)).allTopicNames().get(3, TimeUnit.SECONDS).get(topic);
    }
    static int topic(Options options, Events events, Properties properties) throws Exception {
        Admin admin = Admin.create(properties);
        try { return topic(options, events, admin); }
        finally { admin.close(Duration.ofSeconds(1)); }
    }
    static int topic(Options options, Events events, Admin admin) throws Exception {
        boolean created = false;
        if (options.operation.equals("create")) {
            int partitions = (int) options.positive("partitions", 0, 100000);
            try {
                admin.createTopics(List.of(new NewTopic(options.required("topic"), Optional.of(partitions), Optional.empty())),
                    new CreateTopicsOptions().timeoutMs(3000)).all().get(3, TimeUnit.SECONDS);
                created = true;
            } catch (ExecutionException failure) {
                if (!(failure.getCause() instanceof TopicExistsException)) throw failure;
            }
        }
        TopicDescription description = describe(admin, options.required("topic"));
        int count = description.partitions().size();
        boolean match = !options.operation.equals("create") || count == options.positive("partitions", 0, 100000);
        int code = match ? 0 : 3;
        events.emit("final", match ? "stopped" : "failed", 0, 0, match ? 0 : 1,
            Map.of("topic", options.required("topic"), "partitions", count, "created", created,
                "exit_code", code, "stop_reason", match ? "topic_verified" : "partition_count_mismatch", "unconfirmed_messages", 0));
        return code;
    }

    static final String HELP = """
        Kafka workload (Java 17+, Kafka SDK 3.9.1)
        workload topic create --config FILE --topic NAME --partitions N
        workload topic describe --config FILE --topic NAME
        workload produce --config FILE --topic NAME --run-id ID
          [--rate-mibps 1] [--record-bytes 1024] [--compression none|gzip|snappy|lz4|zstd]
          [--partition-mode round-robin] [--duration-seconds N] [--max-messages N] [--max-errors N]
        workload consume --config FILE --topic NAME --run-id ID --group GROUP
          --start-position current-end|beginning|committed
          [--duration-seconds N] [--max-messages N] [--max-errors N]
        Credentials are read only from FILE (local to the execution host). No resource is deleted,
        no group offset is committed or reset. Start all consumers and wait for every ready event
        before starting producers. Use a dedicated topic. Producer headers carry workload-run-id.
        Consumer messages/payload_bytes count matching run IDs; foreign_* and actual_read_* report
        other records read over the network. Payload bytes are uncompressed value bytes, not wire bytes.
        stdout is schema_version=1 JSONL. max_acked_offsets are inclusive; next_offsets are exclusive.
        Stops close clients within bounded SDK timeouts. Exit: 0 stopped/verified, 2 arguments/runtime,
        3 SDK/config/ACK failure, 4 unconfirmed sends. A stopped empty run is not a successful experiment.
        """;
}
