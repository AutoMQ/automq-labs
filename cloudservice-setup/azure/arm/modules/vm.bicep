@description('Azure region for resource deployment')
param location string

@description('Virtual machine size for the AutoMQ BYOC Console')
param vmSize string

@description('Administrator username for the virtual machine')
param adminUsername string

@description('SSH public key for secure authentication to the virtual machine')
@secure()
param sshPublicKey string

@description('VM image reference configuration for AutoMQ BYOC Console')
param imageReference object

@description('Unique identifier for the deployment, used to generate resource names')
param uniqueId string

@description('Resource ID of the network interface for the virtual machine')
param networkInterfaceId string

@description('Endpoint URL of the operations storage account')
param opsStorageAccountEndpoint string

@description('Resource group name of the virtual network')
param vpcResourceGroupName string = resourceGroup().name

var vmName = 'vm-${uniqueId}'
var osDiskName = 'osdisk-${uniqueId}'
var dataDiskName = 'datadisk-${uniqueId}'
var managedIdentityName = 'id-${uniqueId}'

var linuxConfiguration = {
  disablePasswordAuthentication: true
  ssh: {
    publicKeys: [
      {
        path: '/home/${adminUsername}/.ssh/authorized_keys'
        keyData: sshPublicKey
      }
    ]
  }
}

var customData = reduce(items({
  '\${managedIdentityClientId}': managedIdentity.properties.clientId
  '\${opsContainerName}': 'automq-ops-${uniqueId}'
  '\${opsStorageAccountEndpoint}': opsStorageAccountEndpoint
  '\${uniqueId}': uniqueId
  '\${vpcResourceGroupName}': vpcResourceGroupName
}), loadTextContent('../init.sh'), (cur, next) => replace(string(cur), next.key, next.value))


resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
}

resource dataDisk 'Microsoft.Compute/disks@2023-04-02' = {
  name: dataDiskName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    diskSizeGB: 20
    creationData: {
      createOption: 'Empty'
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: vmName
  location: location
  tags: {
    Name: vmName
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: linuxConfiguration
      customData: base64(customData)
    }
    storageProfile: {
      imageReference: imageReference
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
      dataDisks: [
        {
          lun: 0
          name: dataDiskName
          createOption: 'Attach'
          caching: 'ReadWrite'
          managedDisk: {
            id: dataDisk.id
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterfaceId
        }
      ]
    }
  }
}

output vmId string = vm.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId

