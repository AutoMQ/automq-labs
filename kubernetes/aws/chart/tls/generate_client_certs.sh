#!/bin/bash
CONFIG_PATH="/opt/bitnami/kafka/config"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --password) PASSWORD="$2"; shift ;;
        --namespace) NAMESPACE="$2"; shift ;;
        --pod-name) POD_NAME="$2"; shift ;;
        --config-path) CONFIG_PATH="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$PASSWORD" || -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
    echo "Error: All parameters (--password, --namespace, --pod-name) are required."
    echo "Usage: $0 --password <password> --namespace <namespace> --pod-name <pod-name> "
    exit 1
fi

if [[ ! -f ca-cert || ! -f ca-key ]]; then
    echo "Error: CA certificate (ca-cert) or key (ca-key) not found in current directory."
    exit 1
fi

echo "Generating Kafka client certificate..."
openssl req -newkey rsa:2048 -nodes -keyout kafka-client-key.pem -out kafka-client-csr.pem -subj "/CN=kafka-client"

openssl x509 -req -CA ca-cert -CAkey ca-key -in kafka-client-csr.pem -out kafka-client-cert.pem -days 365 -CAcreateserial -passin pass:"$PASSWORD"

echo "Converting to PKCS12 format..."
openssl pkcs12 -export -in kafka-client-cert.pem -inkey kafka-client-key.pem -out kafka-client.p12 -name kafka-client -passout pass:"$PASSWORD"

echo "Converting to JKS keystore..."
keytool -importkeystore -srckeystore kafka-client.p12 -srcstoretype PKCS12 -destkeystore kafka.client.keystore.jks -deststoretype JKS -srcstorepass "$PASSWORD" -deststorepass "$PASSWORD" -destkeypass "$PASSWORD"

echo "Removing existing CARoot alias from truststore (if any)..."
keytool -delete -alias CARoot -keystore kafka.client.truststore.jks -storepass "$PASSWORD" 2>/dev/null || true

echo "Importing CA certificate to truststore..."
keytool -keystore kafka.client.truststore.jks -alias CARoot -import -file ca-cert -storepass "$PASSWORD" -noprompt

echo "Generating client.properties..."
cat > client.properties << EOF
security.protocol=SSL
ssl.keystore.location=$CONFIG_PATH/kafka.client.keystore.jks
ssl.keystore.password=$PASSWORD
ssl.truststore.location=$CONFIG_PATH/kafka.client.truststore.jks
ssl.truststore.password=$PASSWORD
ssl.key.password=$PASSWORD
EOF

echo "Copying files to pod $POD_NAME in namespace $NAMESPACE..."
kubectl cp client.properties "$NAMESPACE/$POD_NAME:$CONFIG_PATH/" -n "$NAMESPACE"
kubectl cp kafka.client.keystore.jks "$NAMESPACE/$POD_NAME:$CONFIG_PATH/" -n "$NAMESPACE"
kubectl cp kafka.client.truststore.jks "$NAMESPACE/$POD_NAME:$CONFIG_PATH/" -n "$NAMESPACE"

echo "Kafka client certificates and configuration generated and copied successfully! Now you can use them to connect to the Kafka cluster."