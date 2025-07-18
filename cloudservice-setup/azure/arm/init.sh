#!/bin/bash

mkdir -p /opt/cmp 

cat > /opt/cmp/config.properties <<EOF
cmp.provider.credential=vm-role://${managedIdentityClientId}@azure
cmp.provider.opsBucket=${opsContainerName}
cmp.provider.opsBucket.endpoint=${opsStorageAccountEndpoint}
cmp.environmentId=${uniqueId}
cmp.provider.opsBucket.product.code=ObjectStorage
EOF
