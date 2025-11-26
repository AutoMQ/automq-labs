package config

import (
	"os"
	"time"
)

// AutoMQExampleConstants contains configuration constants optimized for AutoMQ's object storage architecture.
// AutoMQ writes data directly to object storage instead of local disks,
// which exhibits higher latency for file creation operations (e.g., P99 latency
// of ~400ms when writing 4MiB files to S3). These configurations help optimize
// throughput and performance for AutoMQ's characteristics.
type AutoMQExampleConstants struct {
	// During testing, you can replace the following configuration with the one in your environment.
	// BOOTSTRAP_SERVERS can be configured via environment variable or defaults to localhost:9092
	BootstrapServers string

	// Topic and Consumer Group Configuration
	TopicName                     string
	TransactionalTopicName        string
	ConsumerGroupID               string
	TransactionalConsumerGroupID  string

	// Number of retries for failed requests.
	// Helps handle transient failures in object storage operations.
	RetriesConfig int

	// Producer Configuration - Optimized for AutoMQ's object storage architecture

	// Metadata refresh interval (60 seconds).
	// The forced refresh time for metadata to prevent routing errors due to metadata expiration.
	// Recommended value for AutoMQ to balance metadata freshness and performance.
	MetadataMaxAge time.Duration

	// Batch size for producer (1MB).
	// The maximum number of bytes in a single batch, directly affecting the number of network requests and throughput.
	BatchSize int32

	// Linger time for batching (100ms).
	// The delay time for the Producer to batch send messages, enhancing the efficiency
	// of each request by accumulating more messages. This helps optimize for AutoMQ's
	// object storage latency characteristics.
	LingerMs time.Duration

	// Maximum request size (16MB).
	// The maximum number of bytes in a single request, limiting the size of messages
	// the Producer can send.
	MaxRequestSize int32

	// Acknowledgment configuration.
	// The server responds to the client only after the data has been persisted to cloud storage.
	// In the event of a server crash, successfully acknowledged messages will not be lost.
	AcksConfig string

	// Consumer Configuration - Optimized for AutoMQ

	// Auto offset reset strategy.
	// "earliest" starts reading from the beginning of the topic when no offset is found.
	AutoOffsetReset string

	// Maximum partition fetch bytes (8MB).
	// Limits the maximum amount of data returned in a Fetch request from a single partition,
	// working together with fetch.max.bytes to control fetch granularity.
	MaxPartitionFetchBytes int32
}

// GetDefaultConstants returns the default configuration constants
func GetDefaultConstants() *AutoMQExampleConstants {
	bootstrapServers := os.Getenv("BOOTSTRAP_SERVERS")
	if bootstrapServers == "" {
		bootstrapServers = "localhost:9092"
	}

	return &AutoMQExampleConstants{
		BootstrapServers:              bootstrapServers,
		TopicName:                     "test-topic",
		TransactionalTopicName:        "trans-test-topic",
		ConsumerGroupID:               "test-consumer-group",
		TransactionalConsumerGroupID:  "trans-consumer-group",
		RetriesConfig:                 3,
		MetadataMaxAge:                60 * time.Second,
		BatchSize:                     1048576, // 1MB
		LingerMs:                      100 * time.Millisecond,
		MaxRequestSize:                16777216, // 16MB
		AcksConfig:                    "all",
		AutoOffsetReset:               "earliest",
		MaxPartitionFetchBytes:        8388608, // 8MB
	}
}