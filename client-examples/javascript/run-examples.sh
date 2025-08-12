#!/bin/sh

# AutoMQ JavaScript Client Examples Runner
# This script provides an easy way to run different examples

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  simple        Run simple message example"
    echo "  transactional Run transactional message example"
    echo "  all           Run all examples"
    echo "  help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 simple"
    echo "  $0 transactional"
    echo "  $0 all"
}

# Function to check if npm dependencies are installed
check_dependencies() {
    if [ ! -d "node_modules" ]; then
        print_info "Installing npm dependencies..."
        npm install
    fi
}

# Function to create logs directory if it doesn't exist
ensure_logs_dir() {
    if [ ! -d "logs" ]; then
        print_info "Creating logs directory..."
        mkdir -p logs
    fi
}

# Function to run simple message example
run_simple() {
    print_info "Running Simple Message Example..."
    npm run simple
    print_success "Simple Message Example completed!"
}

# Function to run transactional message example
run_transactional() {
    print_info "Running Transactional Message Example..."
    npm run transactional
    print_success "Transactional Message Example completed!"
}

# Function to run all examples
run_all() {
    print_info "Running all examples..."
    echo ""
    
    print_info "=== Running Simple Message Example ==="
    run_simple
    echo ""
    
    print_info "=== Running Transactional Message Example ==="
    run_transactional
    echo ""
    
    print_success "All examples completed successfully!"
}

# Main script logic
main() {
    # Check if we're in the right directory
    if [ ! -f "package.json" ]; then
        print_error "package.json not found. Please run this script from the JavaScript client examples directory."
        exit 1
    fi
    
    # Ensure dependencies and logs directory
    check_dependencies
    ensure_logs_dir
    
    # Parse command line arguments
    case "${1:-help}" in
        "simple")
            run_simple
            ;;
        "transactional")
            run_transactional
            ;;
        "all")
            run_all
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"