package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/hamba/avro/v2"
	"github.com/twmb/franz-go/pkg/kadm"
	"github.com/twmb/franz-go/pkg/kgo"
	"github.com/twmb/franz-go/pkg/sr"
)

const (
	kafkaBootstrapServers = "automq:9092"
	topicName             = "web_page_view_events"
	schemaRegistryURL     = "http://schema-registry:8081"
)

// Define Avro Schema with operation support
var schemaStr = `{
  "type": "record",
  "name": "PageViewEvent",
  "namespace": "com.example.events",
  "fields": [
    {"name": "event_id", "type": "string"},
    {"name": "user_id", "type": "string"},
    {"name": "timestamp", "type": { "type": "long", "logicalType": "timestamp-millis" }},
    {"name": "page_url", "type": "string"},
    {"name": "ip_address", "type": "string"},
    {"name": "user_agent", "type": "string"},
    {"name": "ops", "type": "string"}
  ]
}`

// PageViewEvent struct matching the Avro schema
type PageViewEvent struct {
	EventID   string `avro:"event_id"`
	UserID    string `avro:"user_id"`
	Timestamp int64  `avro:"timestamp"`
	PageURL   string `avro:"page_url"`
	IPAddress string `avro:"ip_address"`
	UserAgent string `avro:"user_agent"`
	Ops       string `avro:"ops"`
}

func newClient() *kgo.Client {
	seeds := []string{kafkaBootstrapServers}
	opts := []kgo.Opt{
		kgo.SeedBrokers(seeds...),
		kgo.AllowAutoTopicCreation(),
	}
	client, err := kgo.NewClient(opts...)
	if err != nil {
		log.Fatalf("failed to create kafka client: %v", err)
	}
	return client
}

func createTopic(client *kgo.Client) {
	adm := kadm.NewClient(client)
	topicConfig := map[string]*string{
		"automq.table.topic.enable":             stringPtr("true"),
		"automq.table.topic.commit.interval.ms": stringPtr("2000"),
		"automq.table.topic.schema.type":        stringPtr("schema"),
	}

	resp, err := adm.CreateTopic(context.Background(), 16, 1, topicConfig, topicName)
	if err != nil {
		log.Fatalf("failed to create topic: %v", err)
	}

	if resp.Err != nil {
		if resp.Err.Error() == "TOPIC_ALREADY_EXISTS" {
			fmt.Printf("Topic '%s' already exists.\n", topicName)
		} else {
			log.Fatalf("failed to create topic with error: %v", resp.Err)
		}
	} else {
		fmt.Printf("Topic '%s' created successfully.\n", topicName)
	}
}

func sendMessages(client *kgo.Client, count int) {
	// Initialize Schema Registry client
	rcl, err := sr.NewClient(sr.URLs(schemaRegistryURL))
	if err != nil {
		log.Fatalf("unable to create schema registry client: %v", err)
	}

	// Register schema
	ss, err := rcl.CreateSchema(context.Background(), topicName+"-value", sr.Schema{
		Schema: schemaStr,
		Type:   sr.TypeAvro,
	})
	if err != nil {
		log.Fatalf("unable to create avro schema: %v", err)
	}
	fmt.Printf("created or reusing schema subject %q version %d id %d\n", ss.Subject, ss.Version, ss.ID)

	// Setup serializer
	avroSchema, err := avro.Parse(schemaStr)
	if err != nil {
		log.Fatalf("unable to parse avro schema: %v", err)
	}
	var serde sr.Serde
	serde.Register(
		ss.ID,
		PageViewEvent{},
		sr.EncodeFn(func(v any) ([]byte, error) {
			return avro.Marshal(avroSchema, v)
		}),
		sr.DecodeFn(func(b []byte, v any) error {
			return avro.Unmarshal(avroSchema, b, v)
		}),
	)

	for i := 0; i < count; i++ {
		event := PageViewEvent{
			EventID:   fmt.Sprintf("event-%d-%d", time.Now().UnixNano(), i),
			UserID:    fmt.Sprintf("user-%d", i),
			Timestamp: time.Now().UnixMilli(),
			PageURL:   "https://example.com/page/" + strconv.Itoa(i),
			IPAddress: "192.168.1." + strconv.Itoa(i%255),
			UserAgent: "Go-Avro-Client",
			Ops:       "i",
		}

		payload, err := serde.Encode(event)
		if err != nil {
			log.Printf("failed to encode event: %v", err)
			continue
		}

		record := &kgo.Record{Topic: topicName, Value: payload}
		client.Produce(context.Background(), record, func(r *kgo.Record, err error) {
			if err != nil {
				log.Printf("failed to produce record: %v", err)
			}
		})
	}
	// Flush all records before exiting.
	if err := client.Flush(context.Background()); err != nil {
		log.Fatalf("failed to flush records: %v", err)
	}
	fmt.Printf("[%s] ✅ %d messages written to topic '%s'\n", time.Now().Format(time.RFC3339), count, topicName)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go-producer <create-topic|send-messages> [count]")
		os.Exit(1)
	}

	cmd := os.Args[1]
	client := newClient()
	defer client.Close()

	switch cmd {
	case "create-topic":
		createTopic(client)
	case "send-messages":
		count := 1
		if len(os.Args) > 2 {
			var err error
			count, err = strconv.Atoi(os.Args[2])
			if err != nil {
				log.Fatalf("invalid count: %v", err)
			}
		}
		sendMessages(client, count)
	default:
		fmt.Printf("unknown command: %s\n", cmd)
		os.Exit(1)
	}
}

func stringPtr(s string) *string {
	return &s
}