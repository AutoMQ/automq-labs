#!/usr/bin/env python3
"""
AutoMQ Kafka Client Examples Runner
This script runs Simple message example
"""

import sys
import time
from datetime import datetime
from loguru import logger

from simple_message_example import SimpleMessageExample


def setup_logging():
    """Setup logging configuration"""
    logger.remove()  # Remove default handler
    logger.add(
        sys.stdout,
        format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan>:<cyan>{line}</cyan> - <level>{message}</level>",
        level="INFO"
    )


def run_example(example_class, example_name: str) -> bool:
    """Run example with error handling"""
    logger.info("")
    logger.info(f"=== Running {example_name} ===")
    logger.info(f"Class: {example_class.__name__}")
    logger.info(f"Starting at: {datetime.now()}")
    
    try:
        example = example_class()
        example.run()
        logger.info(f"{example_name} completed successfully at: {datetime.now()}")
        return True
    except Exception as e:
        logger.error(f"Error: {example_name} failed at: {datetime.now()}")
        logger.error(f"Exception: {e}")
        return False


def main():
    """Main function to run all examples"""
    setup_logging()
    
    logger.info("=== AutoMQ Kafka Client Examples Runner ===")
    logger.info(f"Starting at: {datetime.now()}")
    
    success_count = 0
    total_examples = 1
    
    # Run Simple Message Example
    if run_example(SimpleMessageExample, "Simple Message Example"):
        success_count += 1
    
    # Summary
    logger.info("")
    logger.info("=== Execution Summary ===")
    logger.info(f"Total Examples: {total_examples}")
    logger.info(f"Successful: {success_count}")
    logger.info(f"Failed: {total_examples - success_count}")
    logger.info(f"Completed at: {datetime.now()}")
    
    if success_count == total_examples:
        logger.info("All examples completed successfully!")
        sys.exit(0)
    else:
        logger.error("Some examples failed!")
        sys.exit(1)


if __name__ == "__main__":
    main()