FROM confluentinc/cp-schema-registry:7.3.10

USER root

# Install Maven, C++ build tools, and grpcio-tools
RUN microdnf update -y && microdnf install -y \
    maven \
    gcc-c++ \
    python3-pip && \
    microdnf clean all

RUN pip3 install --user grpcio-tools

ENV PATH="/usr/bin:${PATH}"
