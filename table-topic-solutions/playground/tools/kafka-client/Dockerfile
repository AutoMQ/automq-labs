FROM confluentinc/cp-schema-registry:8.1.0

USER root

# Install Maven, C++ build tools, and grpcio-tools
RUN microdnf update -y && microdnf install -y \
    maven \
    gcc-c++ \
    java-17-openjdk-headless \
    python3-devel \
    && microdnf clean all

RUN pip3 install --user grpcio-tools

ENV PATH="/usr/bin:${PATH}"
