#!/usr/bin/env node

const { Command } = require('commander');
const winston = require('winston');
const SimpleMessageExample = require('./examples/simpleMessageExample');
const TransactionalMessageExample = require('./examples/transactionalMessageExample');
const AutoMQConfig = require('./config/automqConfig');

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

const program = new Command();

program
    .name('automq-examples')
    .description('AutoMQ JavaScript/Node.js Client Examples')
    .version('1.0.0');

program
    .command('simple')
    .description('Run simple message producer and consumer example')
    .option('-c, --count <number>', 'Number of messages to send', '20')
    .action(async (options) => {
        logger.info('Starting Simple Message Example...');
        logger.info(`Bootstrap servers: ${AutoMQConfig.BOOTSTRAP_SERVERS}`);
        logger.info(`Topic: ${AutoMQConfig.SIMPLE_TOPIC_NAME}`);
        logger.info(`Message count: ${options.count}`);
        
        try {
            const example = new SimpleMessageExample();
            example.MESSAGE_COUNT = parseInt(options.count);
            await example.run();
        } catch (error) {
            logger.error('Failed to run simple message example:', error);
            process.exit(1);
        }
    });

program
    .command('transactional')
    .description('Run transactional message producer and consumer example')
    .option('-c, --count <number>', 'Number of messages to send', '20')
    .action(async (options) => {
        logger.info('Starting Transactional Message Example...');
        logger.info(`Bootstrap servers: ${AutoMQConfig.BOOTSTRAP_SERVERS}`);
        logger.info(`Topic: ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME}`);
        logger.info(`Message count: ${options.count}`);
        
        try {
            const example = new TransactionalMessageExample();
            example.MESSAGE_COUNT = parseInt(options.count);
            await example.run();
        } catch (error) {
            logger.error('Failed to run transactional message example:', error);
            process.exit(1);
        }
    });

program
    .command('config')
    .description('Display current AutoMQ configuration')
    .action(() => {
        logger.info('=== AutoMQ Configuration ===');
        logger.info(`Bootstrap Servers: ${AutoMQConfig.BOOTSTRAP_SERVERS}`);
        logger.info(`Simple Topic: ${AutoMQConfig.SIMPLE_TOPIC_NAME}`);
        logger.info(`Transactional Topic: ${AutoMQConfig.TRANSACTIONAL_TOPIC_NAME}`);
        logger.info(`Simple Consumer Group: ${AutoMQConfig.SIMPLE_CONSUMER_GROUP_ID}`);
        logger.info(`Transactional Consumer Group: ${AutoMQConfig.TRANSACTIONAL_CONSUMER_GROUP_ID}`);
        logger.info(`Retries: ${AutoMQConfig.RETRIES_CONFIG}`);
        logger.info(`Metadata Max Age: ${AutoMQConfig.METADATA_MAX_AGE_MS}ms`);
        logger.info(`Batch Size: ${AutoMQConfig.BATCH_SIZE}`);
        logger.info(`Linger MS: ${AutoMQConfig.LINGER_MS}ms`);
        logger.info(`Max Request Size: ${AutoMQConfig.MAX_REQUEST_SIZE}`);
        logger.info(`Acks: ${AutoMQConfig.ACKS_CONFIG}`);
        logger.info(`Isolation Level: ${AutoMQConfig.ISOLATION_LEVEL}`);
        logger.info(`Auto Offset Reset: ${AutoMQConfig.AUTO_OFFSET_RESET}`);
        logger.info(`Max Partition Fetch Bytes: ${AutoMQConfig.MAX_PARTITION_FETCH_BYTES}`);
        logger.info(`Session Timeout: ${AutoMQConfig.SESSION_TIMEOUT_MS}ms`);
        logger.info(`Heartbeat Interval: ${AutoMQConfig.HEARTBEAT_INTERVAL_MS}ms`);
        logger.info(`Request Timeout: ${AutoMQConfig.REQUEST_TIMEOUT_MS}ms`);
        logger.info(`Connection Timeout: ${AutoMQConfig.CONNECTION_TIMEOUT_MS}ms`);
        logger.info('============================');
    });

program.parse();

// If no command is provided, show help
if (!process.argv.slice(2).length) {
    program.outputHelp();
}