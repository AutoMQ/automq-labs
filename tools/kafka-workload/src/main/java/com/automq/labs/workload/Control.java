package com.automq.labs.workload;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

final class Control {
    final AtomicBoolean stopped = new AtomicBoolean();
    final CountDownLatch done = new CountDownLatch(1);
    volatile String reason = "stopped";
    volatile Runnable onStop = () -> { };
    void stop(String reason) { if (stopped.compareAndSet(false, true)) { this.reason = reason; onStop.run(); } }
    boolean limit(Options options, Events events, long messages, long errors) {
        if (errors >= options.positive("max-errors", 1, Long.MAX_VALUE)) stop("max_errors");
        if (messages >= options.positive("max-messages", Long.MAX_VALUE, Long.MAX_VALUE)) stop("max_messages");
        if (events.elapsed() >= options.positive("duration-seconds", Long.MAX_VALUE, Long.MAX_VALUE)) stop("duration");
        return stopped.get();
    }
    Thread hook() {
        return new Thread(() -> {
            stop("signal");
            try { done.await(9, TimeUnit.SECONDS); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        }, "workload-shutdown");
    }
}
