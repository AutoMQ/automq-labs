# AutoMQ C++ Client Examples Makefile

# Compiler and flags
CXX = g++
CXXFLAGS = -std=c++11 -Wall -Wextra -O2 -I/opt/homebrew/include -I/opt/homebrew/include/librdkafka -I/usr/include -I/usr/include/librdkafka
LDFLAGS = -L/opt/homebrew/lib -L/usr/lib -L/usr/lib/x86_64-linux-gnu 

# Directories
SRC_DIR = src
OBJ_DIR = obj
BIN_DIR = bin

# Target executable
TARGET = $(BIN_DIR)/automq-cpp-examples

# Source files
SOURCES = $(wildcard $(SRC_DIR)/*.cpp)
OBJECTS = $(SOURCES:$(SRC_DIR)/%.cpp=$(OBJ_DIR)/%.o)

# Default build (with Kafka support)
all: LDFLAGS += -lrdkafka++
all: $(TARGET)

# Build with librdkafka support (requires librdkafka to be installed)
with-kafka: CXXFLAGS += -DWITH_KAFKA
with-kafka: LDFLAGS += -lrdkafka++
with-kafka: all

# Create target executable
$(TARGET): $(OBJECTS) | $(BIN_DIR)
	$(CXX) $(OBJECTS) -o $@ $(LDFLAGS)

# Compile source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.cpp | $(OBJ_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Create directories
$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR)

# Install dependencies (Ubuntu/Debian)
install-deps:
	sudo apt-get update
	sudo apt-get install -y build-essential g++ make librdkafka-dev librdkafka1 pkg-config uuid-dev

# Install dependencies (macOS)
install-deps-mac:
	brew install librdkafka

# Run examples
run: $(TARGET)
	./$(TARGET)

# Run specific example
run-simple: $(TARGET)
	./$(TARGET) simple

# Help target
help:
	@echo "Available targets:"
	@echo "  all           - Build demo version (default)"
	@echo "  with-kafka    - Build with librdkafka support"
	@echo "  clean         - Remove build artifacts"
	@echo "  install-deps  - Install dependencies (Ubuntu/Debian)"
	@echo "  install-deps-mac - Install dependencies (macOS)"
	@echo "  run           - Run all examples"
	@echo "  run-simple    - Run simple message example"
	@echo ""
	@echo "  help          - Show this help message"

.PHONY: all with-kafka clean install-deps install-deps-mac run run-simple help