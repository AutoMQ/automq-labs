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

// SimpleMessageExample demonstrates basic Kafka producer and consumer functionality with performance metrics
type SimpleMessageExample struct {
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

// MessagePayload represents the structure of messages sent
type MessagePayload struct {
	ID        string `json:"id"`
	Timestamp int64  `json:"timestamp"`
	Content   string `json:"content"`
}

// NewSimpleMessageExample creates a new instance of SimpleMessageExample
func NewSimpleMessageExample() *SimpleMessageExample {
	return &SimpleMessageExample{
		constants:    config.GetDefaultConstants(),
		messageCount: 20,
	}
}

// Run executes the simple message example
func (s *SimpleMessageExample) Run() error {
	log.Println("Starting Simple Message Example...")
	log.Printf("Will send and receive %d messages", s.messageCount)

	ctx := context.Background()

	// Create channels for coordination
	consumerReady := make(chan struct{})
	allMessagesReceived := make(chan struct{})

	var wg sync.WaitGroup
	wg.Add(2)

	// Start consumer in a separate goroutine
	go func() {
		defer wg.Done()
		s.runConsumer(ctx, consumerReady, allMessagesReceived)
	}()

	// Wait for consumer to be ready
	<-consumerReady
	time.Sleep(2 * time.Second) // Give consumer time to subscribe

	// Start producer in a separate goroutine
	go func() {
		defer wg.Done()
		s.runProducer(ctx)
	}()

	// Wait for all messages to be received
	<-allMessagesReceived

	// Wait for both goroutines to complete
	wg.Wait()

	// Print performance metrics
	s.printPerformanceMetrics()

	log.Println("Simple Message Example completed.")
	return nil
}

// runProducer creates and runs the Kafka producer
func (s *SimpleMessageExample) runProducer(ctx context.Context) {
	// Create producer client with optimized settings for AutoMQ
	client, err := kgo.NewClient(
		kgo.SeedBrokers(s.constants.BootstrapServers),
		kgo.ProducerBatchMaxBytes(s.constants.BatchSize),
		kgo.ProducerLinger(s.constants.LingerMs),
		kgo.RequestRetries(s.constants.RetriesConfig),
		kgo.RequiredAcks(kgo.AllISRAcks()), // Equivalent to "all"
		kgo.RequestTimeoutOverhead(30*time.Second),
		kgo.MetadataMaxAge(s.constants.MetadataMaxAge),
	)
	if err != nil {
		log.Printf("Error creating producer client: %v", err)
		return
	}
	defer client.Close()

	log.Printf("Producer started, sending %d messages...", s.messageCount)
	s.startTime = time.Now()

	var wg sync.WaitGroup

	for i := 0; i < s.messageCount; i++ {
		messageID := fmt.Sprintf("msg-%d", i)
		sendTime := time.Now().UnixMilli()
		payload := MessagePayload{
			ID:        messageID,
			Timestamp: sendTime,
			Content:   fmt.Sprintf("Hello AutoMQ %d", i),
		}

		messageBytes, err := json.Marshal(payload)
		if err != nil {
			log.Printf("Error marshaling message: %v", err)
			continue
		}

		record := &kgo.Record{
			Topic: s.constants.TopicName,
			Key:   []byte(messageID),
			Value: messageBytes,
		}

		wg.Add(1)
		client.Produce(ctx, record, func(r *kgo.Record, err error) {
			defer wg.Done()
			if err != nil {
				log.Printf("Error producing message %s: %v", messageID, err)
				return
			}

			// Calculate produce latency
			produceLatency := time.Now().UnixMilli() - sendTime
			atomic.AddInt64(&s.totalProdLatency, produceLatency)
			sentCount := atomic.AddInt64(&s.sentCount, 1)

			log.Printf("Sent message %d/%d: key=%s, produceLatency=%dms",
				sentCount, s.messageCount, messageID, produceLatency)
		})
	}

	// Wait for all messages to be sent
	wg.Wait()
	log.Printf("All %d messages sent successfully", s.messageCount)
}

// runConsumer creates and runs the Kafka consumer
func (s *SimpleMessageExample) runConsumer(ctx context.Context, consumerReady chan struct{}, allMessagesReceived chan struct{}) {
	// Create consumer client with optimized settings for AutoMQ
	client, err := kgo.NewClient(
		kgo.SeedBrokers(s.constants.BootstrapServers),
		kgo.ConsumerGroup(s.constants.ConsumerGroupID),
		kgo.ConsumeTopics(s.constants.TopicName),
		kgo.FetchMaxBytes(s.constants.MaxPartitionFetchBytes),
		kgo.ConsumeResetOffset(kgo.NewOffset().AtStart()), // Equivalent to "earliest"
		kgo.RequestRetries(s.constants.RetriesConfig),
		kgo.MetadataMaxAge(s.constants.MetadataMaxAge),
	)
	if err != nil {
		log.Printf("Error creating consumer client: %v", err)
		return
	}
	defer client.Close()

	log.Printf("Consumer subscribed to topic: %s", s.constants.TopicName)
	close(consumerReady)

	for {
		fetches := client.PollFetches(ctx)
		if errs := fetches.Errors(); len(errs) > 0 {
			for _, err := range errs {
				log.Printf("Consumer error: %v", err)
			}
			continue
		}

		fetches.EachPartition(func(p kgo.FetchTopicPartition) {
			for _, record := range p.Records {
				currentCount := atomic.AddInt64(&s.receivedCount, 1)

				// Parse message to get timestamp
				var payload MessagePayload
				if err := json.Unmarshal(record.Value, &payload); err != nil {
					log.Printf("Error unmarshaling message: %v", err)
					continue
				}

				// Calculate end-to-end latency
				e2eLatency := time.Now().UnixMilli() - payload.Timestamp
				atomic.AddInt64(&s.totalE2ELatency, e2eLatency)

				if currentCount == 1 {
					s.mu.Lock()
					s.firstMsgTime = time.Now()
					s.mu.Unlock()
				}

				log.Printf("Received message %d/%d: key=%s, partition=%d, offset=%d, e2eLatency=%dms",
					currentCount, s.messageCount, string(record.Key), record.Partition, record.Offset, e2eLatency)

				if currentCount == int64(s.messageCount) {
					s.mu.Lock()
					s.lastMsgTime = time.Now()
					s.endTime = time.Now()
					s.mu.Unlock()
					close(allMessagesReceived)
					return
				}
			}
		})

		if atomic.LoadInt64(&s.receivedCount) >= int64(s.messageCount) {
			break
		}
	}
}

// printPerformanceMetrics prints detailed performance statistics
func (s *SimpleMessageExample) printPerformanceMetrics() {
	totalTime := s.endTime.Sub(s.startTime)
	consumeTime := s.lastMsgTime.Sub(s.firstMsgTime)

	sentCount := atomic.LoadInt64(&s.sentCount)
	receivedCount := atomic.LoadInt64(&s.receivedCount)
	totalProdLatency := atomic.LoadInt64(&s.totalProdLatency)
	totalE2ELatency := atomic.LoadInt64(&s.totalE2ELatency)

	var avgProduceLatency, avgE2ELatency float64
	if sentCount > 0 {
		avgProduceLatency = float64(totalProdLatency) / float64(sentCount)
	}
	if receivedCount > 0 {
		avgE2ELatency = float64(totalE2ELatency) / float64(receivedCount)
	}

	fmt.Println("\n=== Simple Message Example Performance Metrics ===")
	fmt.Printf("Total Messages: %d\n", s.messageCount)
	fmt.Printf("Messages Sent: %d\n", sentCount)
	fmt.Printf("Messages Received: %d\n", receivedCount)
	fmt.Printf("Total Time: %v\n", totalTime)
	fmt.Printf("Consume Time: %v\n", consumeTime)
	fmt.Printf("Average Produce Latency: %.2f ms\n", avgProduceLatency)
	fmt.Printf("Average End-to-End Latency: %.2f ms\n", avgE2ELatency)
	fmt.Println("=================================================")
}