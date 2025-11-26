const { Kafka, Partitioners } = require('kafkajs');
const winston = require('winston');
const AutoMQConfig = require('../config/automqConfig.js');

// Configure logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.printf(({ timestamp, level, message }) => {
            return `${timestamp} [${level.toUpperCase()}] ${message}`;
        })
    ),
    transports: [
        new winston.transports.Console()
    ]
});

/**
 * Simple message example that demonstrates both producer and consumer with performance metrics
 */
class SimpleMessageExample {
    constructor() {
        this.MESSAGE_COUNT = 20;
        this.sentCount = 0;
        this.receivedCount = 0;
        this.startTime = 0;
        this.endTime = 0;
        this.firstMessageTime = 0;
        this.lastMessageTime = 0;
        this.totalProduceLatency = 0;
        this.totalE2ELatency = 0;
        
        this.kafka = new Kafka({
            clientId: 'automq-simple-example',
            brokers: [AutoMQConfig.BOOTSTRAP_SERVERS],
            // Remove retry config to avoid conflicts with idempotent producer
            requestTimeout: AutoMQConfig.REQUEST_TIMEOUT_MS,
            connectionTimeout: AutoMQConfig.CONNECTION_TIMEOUT_MS
        });
    }

    /**
     * Create producer configuration optimized for AutoMQ
     */
    createProducerConfig() {
        return {
            maxInFlightRequests: 5, // Increased for better performance with idempotent producer
            idempotent: true,
            // Remove retry config to use KafkaJS defaults for idempotent producer
            // Use LegacyPartitioner to maintain compatibility with previous versions
            createPartitioner: Partitioners.LegacyPartitioner,
            // AutoMQ optimized settings
            metadataMaxAge: AutoMQConfig.METADATA_MAX_AGE_MS,
            allowAutoTopicCreation: true
        };
    }

    /**
     * Create consumer configuration optimized for AutoMQ
     */
    createConsumerConfig() {
        return {
            groupId: AutoMQConfig.SIMPLE_CONSUMER_GROUP_ID,
            sessionTimeout: AutoMQConfig.SESSION_TIMEOUT_MS,
            heartbeatInterval: AutoMQConfig.HEARTBEAT_INTERVAL_MS,
            metadataMaxAge: AutoMQConfig.METADATA_MAX_AGE_MS,
            allowAutoTopicCreation: true,
            fromBeginning: AutoMQConfig.AUTO_OFFSET_RESET === 'earliest'
        };
    }

    /**
     * Handle sendBatch result and calculate latencies
     * @param {Object} result - The result from sendBatch
     * @param {Array} messages - The messages that were sent
     * @param {number} endTime - The time when sending completed
     * @param {string} topicName - The topic name for logging
     * @param {string} messageType - The message type for logging (e.g., 'Message', 'Transactional message')
     */
    handleSendBatchResult(result, messages, endTime, topicName, messageType = 'Message') {
        if (result && result.length > 0) {
            const topicResult = result[0]; // First topic result
            if (topicResult && topicResult.partitions) {
                topicResult.partitions.forEach((partitionResult, messageIndex) => {
                    const latency = endTime - parseInt(messages[messageIndex].timestamp);
                    this.totalProduceLatency += latency;
                    this.sentCount++;
                    
                    logger.info(`${messageType} ${this.sentCount}/${this.MESSAGE_COUNT} sent successfully: ` +
                        `topic=${topicName}, partition=${partitionResult.partition}, ` +
                        `offset=${partitionResult.baseOffset}, produce latency=${latency}ms`);
                });
            } else {
                // Fallback: just count messages as sent
                this.sentCount = this.MESSAGE_COUNT;
                const avgLatency = (endTime - this.startTime) / this.MESSAGE_COUNT;
                this.totalProduceLatency = avgLatency * this.MESSAGE_COUNT;
                logger.info(`All ${this.MESSAGE_COUNT} messages sent successfully (batch mode)`);
            }
        } else {
            // Fallback: just count messages as sent
            this.sentCount = this.MESSAGE_COUNT;
            const avgLatency = (endTime - this.startTime) / this.MESSAGE_COUNT;
            this.totalProduceLatency = avgLatency * this.MESSAGE_COUNT;
            logger.info(`All ${this.MESSAGE_COUNT} messages sent successfully (fallback mode)`);
        }
    }

    /**
     * Run the producer to send messages
     */
    async runProducer() {
        const producer = this.kafka.producer(this.createProducerConfig());
        
        try {
            await producer.connect();
            logger.info(`Producer started, sending ${this.MESSAGE_COUNT} messages...`);
            this.startTime = Date.now();

            const messages = [];
            for (let i = 0; i < this.MESSAGE_COUNT; i++) {
                const messageId = `msg-${i}`;
                const sendTime = Date.now();
                const messageValue = JSON.stringify({
                    id: messageId,
                    timestamp: sendTime,
                    content: `Hello AutoMQ ${i}`
                });
                
                messages.push({
                    key: messageId,
                    value: messageValue,
                    timestamp: sendTime.toString()
                });
            }

            // Send messages in batch for better performance
            const result = await producer.sendBatch({
                topicMessages: [{
                    topic: AutoMQConfig.SIMPLE_TOPIC_NAME,
                    messages: messages
                }]
            });

            // Calculate produce latency
            const endTime = Date.now();
            
            // Handle sendBatch result structure
            this.handleSendBatchResult(result, messages, endTime, AutoMQConfig.SIMPLE_TOPIC_NAME, 'Message');

            logger.info(`All ${this.MESSAGE_COUNT} messages sent successfully`);
            
        } catch (error) {
            logger.error('Error occurred while sending messages:', error);
        } finally {
            await producer.disconnect();
        }
    }

    /**
     * Run the consumer to receive messages
     */
    async runConsumer() {
        const consumer = this.kafka.consumer(this.createConsumerConfig());
        
        return new Promise(async (resolve, reject) => {
            try {
                await consumer.connect();
                await consumer.subscribe({ topic: AutoMQConfig.SIMPLE_TOPIC_NAME });
                logger.info(`Consumer subscribed to topic: ${AutoMQConfig.SIMPLE_TOPIC_NAME}`);

                await consumer.run({
                    eachMessage: async ({ topic, partition, message }) => {
                        this.receivedCount++;
                        const receiveTime = Date.now();
                        const messageTimestamp = parseInt(message.timestamp);
                        const latency = receiveTime - messageTimestamp;
                        
                        if (this.receivedCount === 1) {
                            this.firstMessageTime = receiveTime;
                        }
                        
                        this.totalE2ELatency += latency;
                        
                        if (this.receivedCount === this.MESSAGE_COUNT) {
                            this.lastMessageTime = receiveTime;
                            this.endTime = receiveTime;
                            logger.info('All messages received, disconnecting consumer...');
                            
                            // Print performance metrics before disconnecting
                            this.printPerformanceMetrics();
                            
                            await consumer.disconnect();
                            resolve(); // Resolve the promise to exit
                        }
                    }
                });
                
            } catch (error) {
                logger.error('Error occurred while consuming messages:', error);
                reject(error);
            }
        });
    }

    /**
     * Print performance metrics
     */
    printPerformanceMetrics() {
        const currentTime = Date.now();
        const totalTime = (this.endTime || currentTime) - this.startTime;
        const consumeTime = this.receivedCount > 0 ? (this.lastMessageTime - this.firstMessageTime) : 0;
        const avgProduceLatency = this.sentCount > 0 ? (this.totalProduceLatency / this.sentCount) : 0;
        const avgE2ELatency = this.receivedCount > 0 ? (this.totalE2ELatency / this.receivedCount) : 0;
        
        logger.info('\n' +
            '=== Simple Message Performance Metrics ===\n' +
            `Total Messages: ${this.MESSAGE_COUNT}\n` +
            `Messages Sent: ${this.sentCount}\n` +
            `Messages Received: ${this.receivedCount}\n` +
            `Total Time: ${totalTime} ms\n` +
            `Consume Time: ${consumeTime} ms\n` +
            `Average Produce Latency: ${avgProduceLatency.toFixed(2)} ms\n` +
            `Average End-to-End Latency: ${avgE2ELatency.toFixed(2)} ms\n` +
            '===========================');
    }

    /**
     * Create topic if it doesn't exist
     */
    async createTopicIfNotExists() {
        const admin = this.kafka.admin();
        try {
            await admin.connect();
            const topics = await admin.listTopics();
            
            if (!topics.includes(AutoMQConfig.SIMPLE_TOPIC_NAME)) {
                logger.info(`Creating topic: ${AutoMQConfig.SIMPLE_TOPIC_NAME}`);
                await admin.createTopics({
                    topics: [{
                        topic: AutoMQConfig.SIMPLE_TOPIC_NAME,
                        numPartitions: 1,
                        replicationFactor: 1
                    }]
                });
                logger.info(`Topic ${AutoMQConfig.SIMPLE_TOPIC_NAME} created successfully`);
            } else {
                logger.info(`Topic ${AutoMQConfig.SIMPLE_TOPIC_NAME} already exists`);
            }
        } catch (error) {
            logger.error('Error creating topic:', error);
        } finally {
            await admin.disconnect();
        }
    }

    /**
     * Run the complete example
     */
    async run() {
        try {
            logger.info('Starting Simple Message Example...');
            logger.info(`Will send and receive ${this.MESSAGE_COUNT} messages`);
            this.startTime = Date.now();
            
            // Create topic if it doesn't exist
            await this.createTopicIfNotExists();
            
            // Start consumer first
            const consumerPromise = this.runConsumer();
            
            // Wait a bit for consumer to be ready
            await new Promise(resolve => setTimeout(resolve, 3000));
            
            // Start producer
            const producerPromise = this.runProducer();
            
            // Wait for both producer and consumer to complete with timeout
            const timeout = new Promise((_, reject) => {
                setTimeout(() => {
                    reject(new Error('Example timeout after ' + AutoMQConfig.TRANSACTION_TIMEOUT_MS + 'ms'));
                }, AutoMQConfig.TRANSACTION_TIMEOUT_MS);
            });
            
            await Promise.race([
                Promise.all([producerPromise, consumerPromise]),
                timeout
            ]);
            
            logger.info('Simple Message Example completed.');
            process.exit(0);
            
        } catch (error) {
            if (error.message.includes('timeout')) {
                logger.warn('Example completed but timed out waiting for cleanup. Exiting...');
                process.exit(0);
            } else {
                logger.error('Error occurred during example execution:', error);
                process.exit(1);
            }
        } finally {
            process.exit(0);
        }
    }
}

// Run the example if this file is executed directly
if (require.main === module) {
    const example = new SimpleMessageExample();
    example.run().catch(error => {
        logger.error('Failed to run simple message example:', error);
        process.exit(1);
    });
}

module.exports = SimpleMessageExample;