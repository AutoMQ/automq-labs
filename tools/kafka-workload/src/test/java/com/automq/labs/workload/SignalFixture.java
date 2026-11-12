package com.automq.labs.workload;

/** Runs SDK mocks in a child JVM so the tests can deliver a real SIGTERM. */
public final class SignalFixture {
    public static void main(String[] args) {
        WorkloadTest fixture = new WorkloadTest();
        Options options = args[0].equals("consume") ? fixture.consume("--duration-seconds", "30")
            : fixture.produce("--duration-seconds", "30", "--rate-mibps", "1000");
        Control control = new Control();
        Runtime.getRuntime().addShutdownHook(control.hook());
        int code;
        try {
            Events events = new Events(options, System.out);
            code = args[0].equals("consume")
                ? new ConsumerRun(options, events, control, fixture.consumer()).run()
                : new ProducerRun(options, events, control, fixture.producer(false)).run();
        } finally { control.done.countDown(); }
        System.exit(code);
    }
}
