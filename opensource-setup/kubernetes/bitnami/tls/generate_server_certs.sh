#!/bin/bash
CURRENT_DIR=$(pwd)
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --password) PASSWORD="$2"; shift ;;
        --namespace) NAMESPACE="$2"; shift ;;
        --release-name) RELEASE_NAME="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$PASSWORD" || -z "$NAMESPACE" || -z "$RELEASE_NAME" ]]; then
    echo "Error: All parameters (--password, --namespace, --release-name) are required."
    echo "Usage: $0 --password <password> --namespace <namespace> --release-name <release-name>"
    exit 1
fi

KAFKA_SVC_PREFIX="${RELEASE_NAME}-kafka-controller"
KAFKA_BROKER_HEADLESS="${RELEASE_NAME}-kafka-broker-headless.${NAMESPACE}.svc.cluster.local"
KAFKA_SVC_DOMAIN="${RELEASE_NAME}-kafka-controller-headless.${NAMESPACE}.svc.cluster.local"
KAFKA_CLIENT_SVC="${RELEASE_NAME}-kafka.${NAMESPACE}.svc.cluster.local"

WORKDIR=$(mktemp -d)
cd "$WORKDIR" || exit 1

cat > openssl-san.cnf << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = kafka-server

[v3_req]
keyUsage = digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${KAFKA_SVC_PREFIX}-0.${KAFKA_SVC_DOMAIN}
DNS.2 = ${KAFKA_SVC_PREFIX}-1.${KAFKA_SVC_DOMAIN}
DNS.3 = ${KAFKA_SVC_PREFIX}-2.${KAFKA_SVC_DOMAIN}
DNS.4 = *.${KAFKA_SVC_DOMAIN}
DNS.5 = *.${KAFKA_BROKER_HEADLESS}
DNS.6 = ${KAFKA_SVC_DOMAIN}
DNS.7 = ${KAFKA_CLIENT_SVC}
DNS.8 = localhost
EOF

echo "Generating CA certificate..."
openssl req -new -x509 -keyout ca-key -out ca-cert -days 365 -subj "/CN=CA" -passout pass:"$PASSWORD"

echo "Generating Kafka server certificate..."
openssl req -newkey rsa:2048 -nodes -keyout kafka-server-key.pem -out kafka-server-csr.pem -config openssl-san.cnf

openssl x509 -req -CA ca-cert -CAkey ca-key -in kafka-server-csr.pem -out kafka-server-cert.pem -days 365 -CAcreateserial -passin pass:"$PASSWORD" -extensions v3_req -extfile openssl-san.cnf

echo "Converting to PKCS12 format..."
openssl pkcs12 -export -in kafka-server-cert.pem -inkey kafka-server-key.pem -out kafka-server.p12 -name localhost -passout pass:"$PASSWORD"

echo "Converting to JKS keystore..."
keytool -importkeystore -srckeystore kafka-server.p12 -srcstoretype PKCS12 -destkeystore kafka.server.keystore.jks -deststoretype JKS -srcstorepass "$PASSWORD" -deststorepass "$PASSWORD" -destkeypass "$PASSWORD"

echo "Importing CA certificate to keystore..."
keytool -keystore kafka.server.keystore.jks -alias CARoot -import -file ca-cert -storepass "$PASSWORD" -noprompt

echo "Removing existing CARoot alias from truststore (if any)..."
keytool -delete -alias CARoot -keystore kafka.server.truststore.jks -storepass "$PASSWORD" 2>/dev/null || true

echo "Importing CA certificate to truststore..."
keytool -keystore kafka.server.truststore.jks -alias CARoot -import -file ca-cert -storepass "$PASSWORD" -noprompt

echo "Creating Kubernetes secrets..."
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"
kubectl create secret generic kafka-tls-secret \
  --from-file=kafka.keystore.jks=kafka.server.keystore.jks \
  --from-file=kafka.truststore.jks=kafka.server.truststore.jks \
  -n "$NAMESPACE"

kubectl create secret generic kafka-tls-passwords \
  --from-literal=keystore-password="$PASSWORD" \
  --from-literal=truststore-password="$PASSWORD" \
  --from-literal=key-password="$PASSWORD" \
  -n "$NAMESPACE"

echo "Copying ca-cert and ca-key to current directory..."
cp ca-cert ca-key "$CURRENT_DIR"

echo "Cleaning up temporary files..."
cd - || exit 1
rm -rf "$WORKDIR"

echo "Kafka server certificates and secrets generated successfully!"