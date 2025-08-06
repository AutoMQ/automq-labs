package examples

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"

	"github.com/automq/client-examples/go/config"
	"github.com/twmb/franz-go/pkg/kgo"
)

// TransactionalMessageExample demonstrates transactional Kafka operations with ACID guarantees
type TransactionalMessageExample struct {
	constants     *config.AutoMQExampleConstants
	messageCount  int
	sentCount     int64
	receivedCount int64
	startTime     time.Time
	endTime       time.Time
	firstMsgTime  time.Time
	lastMsgTime   time.Time
	totalProdLatency int64
	totalE2ELatency  int64
	mu               sync.Mutex
}

// TransactionalMessagePayload represents the structure of transactional messages sent
type TransactionalMessagePayload struct {
	ID        string `json:"id"`
	Timestamp int64  `json:"timestamp"`
	Content   string `json:"content"`
}

// NewTransactionalMessageExample creates a new instance of TransactionalMessageExample
func NewTransactionalMessageExample() *TransactionalMessageExample {
	return &TransactionalMessageExample{
		constants:    config.GetDefaultConstants(),
		messageCount: 20,
	}
}

// Run executes the transactional message example
func (t *TransactionalMessageExample) Run() error {
	log.Println("Starting Transactional Message Example...")
	log.Printf("Will send and receive %d transactional messages", t.messageCount)

	ctx := context.Background()

	// Create channels for coordination
	consumerReady := make(chan struct{})
	allMessagesReceived := make(chan struct{})

	var wg sync.WaitGroup
	wg.Add(2)

	// Start consumer in a separate goroutine
	go func() {
		defer wg.Done()
		t.runTransactionalConsumer(ctx, consumerReady, allMessagesReceived)
	}()

	// Wait for consumer to be ready
	<-consumerReady
	time.Sleep(2 * time.Second) // Give consumer time to subscribe

	// Start producer in a separate goroutine
	go func() {
		defer wg.Done()
		t.runTransactionalProducer(ctx)
	}()

	// Wait for all messages to be received
	<-allMessagesReceived

	// Wait for both goroutines to complete
	wg.Wait()

	// Print performance metrics
	t.printPerformanceMetrics()

	log.Println("Transactional Message Example completed.")
	return nil
}

// runTransactionalProducer creates and runs the transactional Kafka producer
func (t *TransactionalMessageExample) runTransactionalProducer(ctx context.Context) {
	// Create transactional producer client with optimized settings for AutoMQ
	client, err := kgo.NewClient(
		kgo.SeedBrokers(t.constants.BootstrapServers),
		kgo.TransactionalID("go-transactional-producer"), // Enable transactions
		kgo.ProducerBatchMaxBytes(t.constants.BatchSize),
		kgo.ProducerLinger(t.constants.LingerMs),
		kgo.RequestRetries(t.constants.RetriesConfig),
		kgo.RequiredAcks(kgo.AllISRAcks()), // Equivalent to "all"
		kgo.RequestTimeoutOverhead(30*time.Second),
		kgo.MetadataMaxAge(t.constants.MetadataMaxAge),
	)
	if err != nil {
		log.Printf("Error creating transactional producer client: %v", err)
		return
	}
	defer client.Close()

	log.Printf("Transactional producer started, sending %d messages...", t.messageCount)
	t.startTime = time.Now()

	// Begin transaction
	if err := client.BeginTransaction(); err != nil {
		log.Printf("failed to begin transaction for transactional producer: %v", err)
		return
	}

	var wg sync.WaitGroup
	var hasError int32

	for i := 0; i < t.messageCount; i++ {
		messageID := fmt.Sprintf("txn-msg-%d", i)
		sendTime := time.Now().UnixMilli()
		payload := TransactionalMessagePayload{
			ID:        messageID,
			Timestamp: sendTime,
			Content:   fmt.Sprintf("Hello AutoMQ Transactional %d", i),
		}

		messageBytes, err := json.Marshal(payload)
		if err != nil {
			log.Printf("Error marshaling message: %v", err)
			atomic.StoreInt32(&hasError, 1)
			continue
		}

		record := &kgo.Record{
			Topic: t.constants.TransactionalTopicName,
			Key:   []byte(messageID),
			Value: messageBytes,
		}

		wg.Add(1)
		client.Produce(ctx, record, func(r *kgo.Record, err error) {
			defer wg.Done()
			if err != nil {
				log.Printf("Error producing transactional message %s: %v", messageID, err)
				atomic.StoreInt32(&hasError, 1)
				return
			}

			// Calculate produce latency
			produceLatency := time.Now().UnixMilli() - sendTime
			atomic.AddInt64(&t.totalProdLatency, produceLatency)
			sentCount := atomic.AddInt64(&t.sentCount, 1)

			log.Printf("Sent transactional message %d/%d: key=%s, produceLatency=%dms",
				sentCount, t.messageCount, messageID, produceLatency)
		})
	}

	// Wait for all messages to be sent
	wg.Wait()

	// Check if there were any errors
	if atomic.LoadInt32(&hasError) != 0 {
		log.Println("Error in transaction, aborting...")
		if err := client.EndTransaction(ctx, kgo.TryAbort); err != nil {
			log.Printf("Error aborting transaction: %v", err)
		}
		return
	}

	// Commit transaction
	if err := client.EndTransaction(ctx, kgo.TryCommit); err != nil {
		log.Printf("Error committing transaction: %v", err)
		return
	}

	log.Printf("Transaction committed successfully. All %d messages sent", t.messageCount)
}

// runTransactionalConsumer creates and runs the transactional Kafka consumer
func (t *TransactionalMessageExample) runTransactionalConsumer(ctx context.Context, consumerReady chan struct{}, allMessagesReceived chan struct{}) {
	// Create consumer client with read-committed isolation level for transactional messages
	client, err := kgo.NewClient(
		kgo.SeedBrokers(t.constants.BootstrapServers),
		kgo.ConsumerGroup(t.constants.TransactionalConsumerGroupID),
		kgo.ConsumeTopics(t.constants.TransactionalTopicName),
		kgo.FetchMaxBytes(t.constants.MaxPartitionFetchBytes),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()), // Equivalent to "earliest"
		kgo.FetchIsolationLevel(kgo.ReadCommitted()), // Read only committed messages
		kgo.RequestRetries(t.constants.RetriesConfig),
		kgo.MetadataMaxAge(t.constants.MetadataMaxAge),
	)
	if err != nil {
		log.Printf("Error creating transactional consumer client: %v", err)
		return
	}
	defer client.Close()

	log.Printf("Transactional consumer subscribed to topic: %s", t.constants.TransactionalTopicName)
	close(consumerReady)

	for {
		fetches := client.PollFetches(ctx)
		if errs := fetches.Errors(); len(errs) > 0 {
			for _, err := range errs {
				log.Printf("Transactional consumer error: %v", err)
			}
			continue
		}

		fetches.EachPartition(func(p kgo.FetchTopicPartition) {
			for _, record := range p.Records {
				currentCount := atomic.AddInt64(&t.receivedCount, 1)

				// Parse message to get timestamp
				var payload TransactionalMessagePayload
				if err := json.Unmarshal(record.Value, &payload); err != nil {
					log.Printf("Error unmarshaling transactional message: %v", err)
					continue
				}

				// Calculate end-to-end latency
				e2eLatency := time.Now().UnixMilli() - payload.Timestamp
				atomic.AddInt64(&t.totalE2ELatency, e2eLatency)

				if currentCount == 1 {
					t.mu.Lock()
					t.firstMsgTime = time.Now()
					t.mu.Unlock()
				}

				log.Printf("Received transactional message %d/%d: key=%s, partition=%d, offset=%d, e2eLatency=%dms",
					currentCount, t.messageCount, string(record.Key), record.Partition, record.Offset, e2eLatency)

				if currentCount == int64(t.messageCount) {
					t.mu.Lock()
					t.lastMsgTime = time.Now()
					t.endTime = time.Now()
					t.mu.Unlock()
					close(allMessagesReceived)
					return
				}
			}
		})

		if atomic.LoadInt64(&t.receivedCount) >= int64(t.messageCount) {
			break
		}
	}
}

// printPerformanceMetrics prints detailed performance statistics for transactional operations
func (t *TransactionalMessageExample) printPerformanceMetrics() {
	totalTime := t.endTime.Sub(t.startTime)
	consumeTime := t.lastMsgTime.Sub(t.firstMsgTime)

	sentCount := atomic.LoadInt64(&t.sentCount)
	receivedCount := atomic.LoadInt64(&t.receivedCount)
	totalProdLatency := atomic.LoadInt64(&t.totalProdLatency)
	totalE2ELatency := atomic.LoadInt64(&t.totalE2ELatency)

	var avgProduceLatency, avgE2ELatency float64
	if sentCount > 0 {
		avgProduceLatency = float64(totalProdLatency) / float64(sentCount)
	}
	if receivedCount > 0 {
		avgE2ELatency = float64(totalE2ELatency) / float64(receivedCount)
	}

	fmt.Println("\n=== Transactional Message Example Performance Metrics ===")
	fmt.Printf("Total Messages: %d\n", t.messageCount)
	fmt.Printf("Messages Sent: %d\n", sentCount)
	fmt.Printf("Messages Received: %d\n", receivedCount)
	fmt.Printf("Total Time: %v\n", totalTime)
	fmt.Printf("Consume Time: %v\n", consumeTime)
	fmt.Printf("Average Produce Latency: %.2f ms\n", avgProduceLatency)
	fmt.Printf("Average End-to-End Latency: %.2f ms\n", avgE2ELatency)
	fmt.Println("============================================================")
}