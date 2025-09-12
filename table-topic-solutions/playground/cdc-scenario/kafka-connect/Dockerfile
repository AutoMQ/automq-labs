# Base image
FROM quay.io/debezium/connect:3.2

# Confluent version
ARG CONFLUENT_VERSION=7.9.2
ENV PLUGIN_DIR=/kafka/connect/plugins

# Create the plugin directory if it doesn't exist
RUN mkdir -p $PLUGIN_DIR

# Download necessary JARs and place them in the plugin directory
# ref: https://debezium.io/documentation/reference/stable/configuration/avro.html#:~:text=A%20Debezium%20connector%20works%20in,Applies%20configured%20transformations.
RUN curl -L -o $PLUGIN_DIR/kafka-connect-avro-converter.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-connect-avro-converter/7.3.0/kafka-connect-avro-converter-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/kafka-connect-avro-data.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-connect-avro-data/7.3.0/kafka-connect-avro-data-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/kafka-avro-serializer.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-avro-serializer/7.3.0/kafka-avro-serializer-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/kafka-schema-serializer.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-schema-serializer/7.3.0/kafka-schema-serializer-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/kafka-schema-converter.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-schema-converter/7.3.0/kafka-schema-converter-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/kafka-schema-registry-client.jar \
    https://packages.confluent.io/maven/io/confluent/kafka-schema-registry-client/7.3.0/kafka-schema-registry-client-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/common-config.jar \
    https://packages.confluent.io/maven/io/confluent/common-config/7.3.0/common-config-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/common-utils.jar \
    https://packages.confluent.io/maven/io/confluent/common-utils/7.3.0/common-utils-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/avro.jar \
    https://repo1.maven.org/maven2/org/apache/avro/avro/1.10.2/avro-1.10.2.jar && \
    curl -L -o $PLUGIN_DIR/commons-compress.jar \
    https://repo1.maven.org/maven2/org/apache/commons/commons-compress/1.21/commons-compress-1.21.jar && \
    curl -L -o $PLUGIN_DIR/failureaccess.jar \
    https://repo1.maven.org/maven2/com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1.jar && \
    curl -L -o $PLUGIN_DIR/guava.jar \
    https://repo1.maven.org/maven2/com/google/guava/guava/31.1-jre/guava-31.1-jre.jar && \
    curl -L -o $PLUGIN_DIR/minimal-json.jar \
    https://repo1.maven.org/maven2/com/eclipsesource/minimal-json/minimal-json/0.9.5/minimal-json-0.9.5.jar && \
    curl -L -o $PLUGIN_DIR/re2j.jar \
    https://repo1.maven.org/maven2/com/google/re2j/re2j/1.3/re2j-1.3.jar && \
    curl -L -o $PLUGIN_DIR/slf4j-api.jar \
    https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.32/slf4j-api-1.7.32.jar && \
    curl -L -o $PLUGIN_DIR/snakeyaml.jar \
    https://repo1.maven.org/maven2/org/yaml/snakeyaml/1.30/snakeyaml-1.30.jar && \
    curl -L -o $PLUGIN_DIR/swagger-annotations.jar \
    https://repo1.maven.org/maven2/io/swagger/swagger-annotations/1.6.4/swagger-annotations-1.6.4.jar && \
    curl -L -o $PLUGIN_DIR/jackson-databind.jar \
    https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-databind/2.13.3/jackson-databind-2.13.3.jar && \
    curl -L -o $PLUGIN_DIR/jackson-core.jar \
    https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-core/2.13.3/jackson-core-2.13.3.jar && \
    curl -L -o $PLUGIN_DIR/jackson-annotations.jar \
    https://repo1.maven.org/maven2/com/fasterxml/jackson/core/jackson-annotations/2.13.3/jackson-annotations-2.13.3.jar && \
    curl -L -o $PLUGIN_DIR/jackson-dataformat-csv.jar \
    https://repo1.maven.org/maven2/com/fasterxml/jackson/dataformat/jackson-dataformat-csv/2.13.3/jackson-dataformat-csv-2.13.3.jar && \
    curl -L -o $PLUGIN_DIR/logredactor.jar \
    https://repo1.maven.org/maven2/io/confluent/logredactor/7.3.0/logredactor-7.3.0.jar && \
    curl -L -o $PLUGIN_DIR/logredactor-metrics.jar \
    https://repo1.maven.org/maven2/io/confluent/logredactor-metrics/7.3.0/logredactor-metrics-7.3.0.jar
