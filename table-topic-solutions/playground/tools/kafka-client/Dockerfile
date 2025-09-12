FROM confluentinc/cp-schema-registry:latest

USER root

# Install Maven, C++ build tools, and grpcio-tools
RUN yum update -y && yum install -y \
    maven \
    gcc-c++ \
    python3-pip

RUN pip3 install --user grpcio-tools

ENV PATH="/usr/bin:${PATH}"
