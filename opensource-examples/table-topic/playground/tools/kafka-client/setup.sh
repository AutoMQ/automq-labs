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

echo "Python setup complete"
# Keep container running
exec sleep infinity