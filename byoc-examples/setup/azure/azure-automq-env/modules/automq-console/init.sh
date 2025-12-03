#!/bin/bash

set -euo pipefail

mkdir -p /opt/cmp

cat > /opt/cmp/config.properties <<EOF2
cmp.provider.credential=vm-role://${managedIdentityClientId}@azure
cmp.provider.opsBucket=${opsContainerName}
cmp.provider.opsBucket.endpoint=${opsStorageAccountEndpoint}
cmp.environmentId=${uniqueId}
cmp.provider.opsBucket.product.code=ObjectStorage
cmp.provider.clusterVpc=vpcId/${vpcName}/resourceGroup/${vpcResourceGroupName}
EOF2
