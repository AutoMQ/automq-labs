#!/bin/bash

# AutoMQ Python Kafka Client Examples Runner
# This script provides easy ways to run the Python examples

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== AutoMQ Python Kafka Client Examples Runner ==="
echo "Project directory: $SCRIPT_DIR"

# Function to check if Python is available
check_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        echo "Error: Python is not installed or not in PATH"
        exit 1
    fi
    echo "Using Python: $PYTHON_CMD"
}

# Function to install dependencies
install_deps() {
    echo "Installing Python dependencies..."
    $PYTHON_CMD -m pip install -r requirements.txt
    echo "Dependencies installed successfully"
}

# Function to run examples
run_examples() {
    echo "Running AutoMQ Python examples..."
    $PYTHON_CMD run_examples.py
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [install|help]"
    echo ""
    echo "Commands:"
    echo "  install     Install Python dependencies"
    echo "  help        Show this help message"
    echo "  (default)   Run examples"
    echo ""
    echo "Environment Variables:"
    echo "  BOOTSTRAP_SERVERS   Kafka broker addresses (default: localhost:9092)"
}

# Main logic
case "${1:-}" in
    "install")
        check_python
        install_deps
        ;;
    "help")
        show_usage
        ;;
    "")
        check_python
        run_examples
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac