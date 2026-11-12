package com.automq.labs.workload;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import java.io.*;
import java.nio.file.Path;
import java.util.concurrent.*;
import static org.junit.jupiter.api.Assertions.*;

class LifecycleTest {
    @Test void sigtermConsumerEmitsFinalAndStopsWithinBound() throws Exception { signal("consume", 0, "TERM"); }
    @Test void sigtermProducerKeepsUnconfirmedSendsVisible() throws Exception { signal("produce", 4, "TERM"); }
    @Test void sigintConsumerEmitsFinalAndStopsWithinBound() throws Exception { signal("consume", 0, "INT"); }
    @Test void sigintProducerKeepsUnconfirmedSendsVisible() throws Exception { signal("produce", 4, "INT"); }
    private void signal(String role, int finalCode, String signal) throws Exception {
        Process process = new ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "java").toString(), "-cp",
            System.getProperty("java.class.path"), SignalFixture.class.getName(), role).redirectErrorStream(true).start();
        ExecutorService reader = Executors.newSingleThreadExecutor();
        try {
            BufferedReader lines = process.inputReader();
            Future<String> first = reader.submit(lines::readLine);
            assertNotNull(first.get(5, TimeUnit.SECONDS));
            long signalTime = System.nanoTime();
            Process kill = new ProcessBuilder("/bin/kill", "-" + signal, Long.toString(process.pid())).start();
            assertEquals(0, kill.waitFor());
            assertTrue(process.waitFor(6, TimeUnit.SECONDS), "Signal must not leave an unbounded JVM");
            String rest = lines.lines().reduce("", (a, b) -> a + b + "\n");
            var finalFrame = rest.lines().map(line -> {
                try { return new ObjectMapper().readTree(line); } catch (Exception failure) { throw new AssertionError(line); }
            }).filter(frame -> frame.path("event").asText().equals("final")).findFirst().orElseThrow();
            assertEquals(finalCode, finalFrame.get("exit_code").asInt());
            assertEquals("signal", finalFrame.get("stop_reason").asText());
            if (role.equals("produce")) assertTrue(finalFrame.get("unconfirmed_messages").asInt() > 0);
            assertTrue(TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - signalTime) < 6);
        } finally { process.destroyForcibly(); reader.shutdownNow(); }
    }
}
