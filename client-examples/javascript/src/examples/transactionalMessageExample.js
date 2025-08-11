const { Kafka, Partitioners } = require('kafkajs');
const winston = require('winston');
const { v4: uuidv4 } = require('uuid');
const AutoMQConfig = require('../config/automqConfig');

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
 * Transactional message example that demonstrates both transactional producer and consumer with performance metrics
 */
class TransactionalMessageExample {
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
        this.transactionalId = `txn-producer-${uuidv4()}`;
        
        this.kafka = new Kafka({
            clientId: 'automq-transactional-example',
            brokers: [AutoMQConfig.BOOTSTRAP_SERVERS],
            // Remove retry config to avoid conflicts with idempotent producer
            requestTimeout: AutoMQConfig.REQUEST_TIMEOUT_MS,
            connectionTimeout: AutoMQConfig.CONNECTION_TIMEOUT_MS
        });
    }

    /**
     * Create transactional producer configuration optimized for AutoMQ
     */
    createTransactionalProducerConfig() {
        return {
            transactionTimeout: 10000,
            transactionalId: this.transactionalId,
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
     * Create transactional consumer configuration optimized for AutoMQ
     */
    createTransactionalConsumerConfig() {
        return {
            groupId: AutoMQConfig.TRANSACTIONAL_CONSUMER_GROUP_ID,
            sessionTimeout: AutoMQConfig.SESSION_TIMEOUT_MS,
            heartbeatInterval: AutoMQConfig.HEARTBEAT_INTERVAL_MS,
            metadataMaxAge: AutoMQConfig.METADATA_MAX_AGE_MS,
            allowAutoTopicCreation: true,
            // Read only committed messages in transactional scenarios
            isolationLevel: AutoMQConfig.ISOLATION_LEVEL,
            fromBeginning: AutoMQConfig.AUTO_OFFSET_RESET === 'earliest'
        };
    }

    /**
     * Handle sendBatch result and calculate latencies for transactional messages
     * @param {Object} result - The result from sendBatch
     * @param {Array} messages - The messages that were sent
     * @param {number} endTime - The time when sending completed
     * @param {string} topicName - The topic name for logging
     * @param {string} messageType - The message type for logging (e.g., 'Transactional message')
     */
    handleTransactionalSendBatchResult(result, messages, endTime, topicName, messageType = 'Transactional message') {
        if (result && result.length > 0) {
            const topicResult = result[0]; // First topic result
            if (topicResult && topicResult.partitions) {
                topicResult.partitions.forEach((partitionResult, messageIndex) => {
                    const latency = endTime - parseInt(messages[messageIndex].timestamp);
                    this.totalProduceLatency += latency;
                    this.sentCount++;
                    
                    logger.info(`${messageType} ${this.sentCount}/${this.MESSAGE_COUNT} sent: ` +
                        `topic=${topicName}, ` +
                        `partition=${partitionResult.partition}, ` +
                        `offset=${partitionResult.baseOffset}, produce latency=${latency}ms`);
                });
            } else {
                // Fallback: just count messages as sent
                this.sentCount = this.MESSAGE_COUNT;
                const avgLatency = (endTime - this.startTime) / this.MESSAGE_COUNT;
                this.totalProduceLatency = avgLatency * this.MESSAGE_COUNT;
                logger.info(`All ${this.MESSAGE_COUNT} transactional messages sent successfully (batch mode)`);
            }
        } else {
            // Fallback: just count messages as sent
            this.sentCount = this.MESSAGE_COUNT;
            const avgLatency = (endTime - this.startTime) / this.MESSAGE_COUNT;
            this.totalProduceLatency = avgLatency * this.MESSAGE_COUNT;
            logger.info(`All ${this.MESSAGE_COUNT} transactional messages sent successfully (fallback mode)`);
        }
    }

    /**
     * Run the transactional producer to send messages
     */
    async runTransactionalProducer() {
        const producer = this.kafka.producer(this.createTransactionalProducerConfig());
        
        try {
            await producer.connect();
            logger.info(`Transactional producer started, sending ${this.MESSAGE_COUNT} messages...`);
            this.startTime = Date.now();

            // Begin transaction
            const transaction = await producer.transaction();
            
            try {
                const messages = [];
                for (let i = 0; i < this.MESSAGE_COUNT; i++) {
                    const messageId = `txn-msg-${i}`;
                    const sendTime = Date.now();
                    const messageValue = JSON.stringify({
                        id: messageId,
                        timestamp: sendTime,
                        content: `Hello AutoMQ Transactional ${i}`,
                        transactionId: this.transactionalId
                    });
                    
                    messages.push({
                        key: messageId,
                        value: messageValue,
                        timestamp: sendTime.toString()
                    });
                }

                // Send messages within transaction
                const result = await transaction.sendBatch({
                    topicMessages: [{
                        topic: AutoMQConfig.TRANSACTIONAL_TOPIC_NAME,
                        messages: messages
                    }]
                });

                // Calculate produce latency
                const endTime = Date.now();
                
                // Handle sendBatch result structure for transactions
                this.handleTransactionalSendBatchResult(result, messages, endTime, AutoMQConfig.TRANSACTIONAL_TOPIC_NAME, 'Transactional message');

                // Commit transaction
                await transaction.commit();
                logger.info(`Transaction committed successfully. All ${this.MESSAGE_COUNT} messages sent.`);
                
            } catch (error) {
                logger.error('Error in transaction, rolling back:', error);
                await transaction.abort();
                throw error;
            }
            
        } catch (error) {
            logger.error('Error occurred while sending transactional messages:', error);
        } finally {
            await producer.disconnect();
        }
    }

    /**
     * Run the transactional consumer to receive messages
     */
    async runTransactionalConsumer() {
        const consumer = this.kafka.consumer(this.createTransactionalConsumerConfig());
        
        return new Promise(async (resolve, reject) => {
            try {
                await consumer.connect();
                await consumer.subscribe({ topic: AutoMQConfig.TRANSACTIONAL_TOPIC_NAME });
                logger.info(`Transactional consumer subscribed to topic: ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME}`);
                logger.info(`Consumer isolation level: ${AutoMQConfig.ISOLATION_LEVEL}`);

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
                        
                        // Parse message to get transaction info
                        let messageData = {};
                        try {
                            messageData = JSON.parse(message.value.toString());
                        } catch (e) {
                            messageData = { content: message.value.toString() };
                        }
                        
                        if (this.receivedCount === this.MESSAGE_COUNT) {
                            this.lastMessageTime = receiveTime;
                            this.endTime = receiveTime;
                            logger.info('All transactional messages received, disconnecting consumer...');
                            
                            // Print performance metrics before disconnecting
                            this.printPerformanceMetrics();
                            
                            await consumer.disconnect();
                            resolve(); // Resolve the promise to exit
                        }
                    }
                });
                
            } catch (error) {
                logger.error('Error occurred while consuming transactional messages:', error);
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
            '=== Transactional Performance Metrics ===\n' +
            `Total Messages: ${this.MESSAGE_COUNT}\n` +
            `Messages Sent: ${this.sentCount}\n` +
            `Messages Received: ${this.receivedCount}\n` +
            `Total Time: ${totalTime} ms\n` +
            `Consume Time: ${consumeTime} ms\n` +
            `Average Produce Latency: ${avgProduceLatency.toFixed(2)} ms\n` +
            `Average End-to-End Latency: ${avgE2ELatency.toFixed(2)} ms\n` +
            `Transaction ID: ${this.transactionalId}\n` +
            `Isolation Level: ${AutoMQConfig.ISOLATION_LEVEL}\n` +
            '==========================================');
    }

    /**
     * Create topic if it doesn't exist
     */
    async createTopicIfNotExists() {
        const admin = this.kafka.admin();
        try {
            await admin.connect();
            const topics = await admin.listTopics();
            
            if (!topics.includes(AutoMQConfig.TRANSACTIONAL_TOPIC_NAME)) {
                logger.info(`Creating topic: ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME}`);
                await admin.createTopics({
                    topics: [{
                        topic: AutoMQConfig.TRANSACTIONAL_TOPIC_NAME,
                        numPartitions: 3,
                        replicationFactor: 1
                    }]
                });
                logger.info(`Topic ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME} created successfully`);
            } else {
                logger.info(`Topic ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME} already exists`);
            }
        } catch (error) {
            logger.error('Error creating topic:', error);
        } finally {
            await admin.disconnect();
        }
    }

    /**
     * Run the complete transactional example
     */
    async run() {
        logger.info('Starting Transactional Message Example...');
        logger.info(`Will send and receive ${this.MESSAGE_COUNT} transactional messages`);
        logger.info(`Transaction ID: ${this.transactionalId}`);

        try {
            // Create topic if it doesn't exist
            await this.createTopicIfNotExists();
            
            // Start consumer first
            const consumerPromise = this.runTransactionalConsumer();
            
            // Wait a bit for consumer to be ready
            await new Promise(resolve => setTimeout(resolve, 3000));
            
            // Start transactional producer
            const producerPromise = this.runTransactionalProducer();
            
            // Wait for both producer and consumer to finish with a timeout
            await Promise.race([
                Promise.all([producerPromise, consumerPromise]),
                new Promise((_, reject) => 
                    setTimeout(() => reject(new Error('Timeout waiting for completion')), 30000)
                )
            ]);
            
            logger.info('Transactional Message Example completed.');
            
        } catch (error) {
            if (error.message === 'Timeout waiting for completion') {
                logger.info('Example completed but timed out waiting for cleanup. Exiting...');
            } else {
                logger.error('Error occurred during transactional message example:', error);
            }
        } finally {
            // Force exit after a short delay to allow final logs
            setTimeout(() => {
                process.exit(0);
            }, 1000);
        }
    }
}

// Run the example if this file is executed directly
if (require.main === module) {
    const example = new TransactionalMessageExample();
    example.run().catch(error => {
        logger.error('Failed to run transactional message example:', error);
        process.exit(1);
    });
}

module.exports = TransactionalMessageExample;