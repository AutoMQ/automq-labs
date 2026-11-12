# Workload options and result fields

Return to the [quick start](../README.md) for the single-producer example. Run `./workload --help` from `tools/kafka-workload` for supported arguments.

## Read progress and finish a run

Stdout is versioned JSONL. Producer `messages` and `payload_bytes` count acknowledged writes; `max_acked_offsets` are inclusive. Consumer counts matching `workload-run-id` records; `actual_read_*` and `foreign_*` expose other data read. `next_offsets` are exclusive. Payload bytes are uncompressed record values, not network or billing bytes.

Stop the producer first and inspect its `final` event. For each partition, the consumer must reach at least the largest successfully acknowledged producer offset plus one. Keep consumers running until that boundary is reached, then stop them with Ctrl+C. A consumer without a message/duration limit waits for data; it does not infer that a producer is finished. Do not accept errors, unconfirmed writes or an empty run as a completed experiment.

Both roles support `--duration-seconds`, `--max-messages` and `--max-errors` when a bounded standalone run is needed. Limits are per process. Do not give a reader the per-producer message limit when it must read several producers' combined output. Ctrl+C requests bounded SDK shutdown and emits a final event. Exit codes are `0` stopped/verified, `2` arguments/runtime, `3` SDK/configuration/ACK failure, and `4` unconfirmed sends.


## Launcher configuration

`target/workload.jar` is resolved relative to the launcher, so `workload` can run from another directory. `JAVA_HOME` selects Java, and `WORKLOAD_JAR` can select another readable fat JAR. Supported compression values are `none`, `gzip`, `snappy`, `lz4` and `zstd`; partition mode is `round-robin`. The default producer rate is 1 MiB/s when `--rate-mibps` is omitted.
