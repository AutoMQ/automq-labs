package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/automq/client-examples/go/examples"
)

func main() {
	// Parse command line flags
	exampleType := flag.String("example", "all", "Type of example to run: 'simple', 'transactional', or 'all'")
	flag.Parse()

	log.Println("=== AutoMQ Kafka Client Examples Runner ===")
	log.Printf("Starting at: %s", time.Now().Format(time.RFC3339))

	switch *exampleType {
	case "simple":
		runSimpleExample()
	case "transactional":
		runTransactionalExample()
	case "all":
		runAllExamples()
	default:
		fmt.Printf("Unknown example type: %s\n", *exampleType)
		fmt.Println("Available options: 'simple', 'transactional', 'all'")
		os.Exit(1)
	}

	log.Println("=== All examples completed ===")
	log.Printf("Finished at: %s", time.Now().Format(time.RFC3339))
}

// runSimpleExample runs the simple message example
func runSimpleExample() {
	log.Println("\n=== Running Simple Message Example ===")
	log.Printf("Starting at: %s", time.Now().Format(time.RFC3339))

	example := examples.NewSimpleMessageExample()
	if err := example.Run(); err != nil {
		log.Printf("Error: Simple Message Example failed: %v", err)
		os.Exit(1)
	}

	log.Printf("Simple Message Example completed successfully at: %s", time.Now().Format(time.RFC3339))
}

// runTransactionalExample runs the transactional message example
func runTransactionalExample() {
	log.Println("\n=== Running Transactional Message Example ===")
	log.Printf("Starting at: %s", time.Now().Format(time.RFC3339))

	example := examples.NewTransactionalMessageExample()
	if err := example.Run(); err != nil {
		log.Printf("Error: Transactional Message Example failed: %v", err)
		os.Exit(1)
	}

	log.Printf("Transactional Message Example completed successfully at: %s", time.Now().Format(time.RFC3339))
}

// runAllExamples runs both simple and transactional examples
func runAllExamples() {
	// Run Simple Message Example
	runSimpleExample()

	log.Println("\nWaiting 1 second before running next example...")
	time.Sleep(1 * time.Second)

	// Run Transactional Message Example
	runTransactionalExample()
}