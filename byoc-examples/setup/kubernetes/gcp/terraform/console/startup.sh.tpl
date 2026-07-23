#!/bin/bash
set -euo pipefail

decode() {
  printf '%s' "$1" | base64 -d
}

CONSOLE_IMAGE="$(decode '${console_image_b64}')"
CONFIG="$(decode '${config_b64}')"
HOME_ENDPOINT="$(decode '${home_endpoint_b64}')"
INITIAL_PASSWORD="$(decode '${initial_password_b64}')"
ACCESS_KEY="$(decode '${access_key_b64}')"
SECRET_KEY="$(decode '${secret_key_b64}')"
SERVICE_ACCOUNT="$(decode '${service_account_b64}')"
REGISTRY_SERVER="$(decode '${registry_server_b64}')"
REGISTRY_USERNAME="$(decode '${registry_username_b64}')"
REGISTRY_PASSWORD="$(decode '${registry_password_b64}')"

if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates docker.io
fi
systemctl enable --now docker

DATA_DEVICE="/dev/disk/by-id/google-automq-console-data"
while [ ! -e "$DATA_DEVICE" ]; do
  sleep 1
done

if ! blkid "$DATA_DEVICE"; then
  mkfs.ext4 -F "$DATA_DEVICE"
fi

mkdir -p /data
if ! mountpoint -q /data; then
  mount "$DATA_DEVICE" /data
fi
grep -q " /data " /etc/fstab || echo "$DATA_DEVICE /data ext4 defaults,nofail 0 2" >> /etc/fstab

if docker container inspect automq-console >/dev/null 2>&1; then
  docker start automq-console >/dev/null
  exit 0
fi

if [ -n "$REGISTRY_SERVER" ]; then
  printf '%s' "$REGISTRY_PASSWORD" | docker login \
    --username "$REGISTRY_USERNAME" \
    --password-stdin \
    "$REGISTRY_SERVER"
fi

docker run -d \
  --name automq-console \
  --restart unless-stopped \
  --net=host \
  -v /data:/root \
  -e CONFIG="$CONFIG" \
  -e CLOUD_PROVIDER=gcp \
  -e HOME_ENDPOINT="$HOME_ENDPOINT" \
  -e CONSOLE_INITIAL_USER=admin \
  -e CONSOLE_INITIAL_PASSWORD="$INITIAL_PASSWORD" \
  -e CONSOLE_INITIAL_ACCESS_KEY="$ACCESS_KEY" \
  -e CONSOLE_INITIAL_SECRET_KEY="$SECRET_KEY" \
  -e CONSOLE_PORT=8080 \
  -e GCP_SERVICE_ACCOUNT="$SERVICE_ACCOUNT" \
  "$CONSOLE_IMAGE"
