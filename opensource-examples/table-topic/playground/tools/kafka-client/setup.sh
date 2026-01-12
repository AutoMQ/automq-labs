#!/bin/bash

# Install Python dependencies for protobuf sample
echo "Installing Python dependencies for protobuf sample..."
pip3 install -r /home/kafka-client/sample/protobuf-sample/requirements.txt

# Install Python dependencies for avro sample
echo "Installing Python dependencies for avro sample..."
pip3 install -r /home/kafka-client/sample/avro-sample/requirements.txt

# Generate protobuf Python classes
echo "Generating protobuf Python classes..."
python3 -m grpc_tools.protoc \
  -I/home/kafka-client/sample/protobuf-sample/schema \
  --python_out=/home/kafka-client/sample/protobuf-sample \
  /home/kafka-client/sample/protobuf-sample/schema/user.proto \
  /home/kafka-client/sample/protobuf-sample/schema/product.proto \
  /home/kafka-client/sample/protobuf-sample/schema/common.proto

# Generate event-related protobuf Python classes
echo "Generating event-related protobuf Python classes..."
# Create __init__.py files for Python package structure first
mkdir -p /home/kafka-client/sample/protobuf-sample/examples/clients/core
mkdir -p /home/kafka-client/sample/protobuf-sample/examples/clients/platform
touch /home/kafka-client/sample/protobuf-sample/examples/__init__.py
touch /home/kafka-client/sample/protobuf-sample/examples/clients/__init__.py
touch /home/kafka-client/sample/protobuf-sample/examples/clients/core/__init__.py
touch /home/kafka-client/sample/protobuf-sample/examples/clients/platform/__init__.py

# Generate with consistent proto_path
python3 -m grpc_tools.protoc \
  -I/home/kafka-client/sample/protobuf-sample/schema/events \
  --python_out=/home/kafka-client/sample/protobuf-sample \
  /home/kafka-client/sample/protobuf-sample/schema/events/examples/clients/core/common_structs.proto

python3 -m grpc_tools.protoc \
  -I/home/kafka-client/sample/protobuf-sample/schema/events \
  --python_out=/home/kafka-client/sample/protobuf-sample \
  /home/kafka-client/sample/protobuf-sample/schema/events/examples/clients/platform/stream_info.proto

python3 -m grpc_tools.protoc \
  -I/home/kafka-client/sample/protobuf-sample/schema/events \
  --python_out=/home/kafka-client/sample/protobuf-sample \
  /home/kafka-client/sample/protobuf-sample/schema/events/event.proto

echo "Python setup complete"
# Keep container running
exec sleep infinity