metadata description = 'Deploy AutoMQ BYOC Console with secure virtual machine configuration, SSH authentication, and customizable networking options'
var uniqueId = uniqueString(resourceGroup().id, deployment().name)

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Determines whether to create a new virtual network or use an existing one')
@allowed([
  'existing'
  'new'
])
param virtualNetworkNewOrExisting string = 'new'

@description('Name of the virtual network for the AutoMQ BYOC Console deployment')
param virtualNetworkName string = ''

@description('Resource group name containing the virtual network (defaults to current resource group)')
param virtualNetworkResourceGroup string = resourceGroup().name

@description('Address prefix for the new virtual network (CIDR notation)')
param virtualNetworkAddressPrefix string = '10.0.0.0/16'

@description('Name of the subnet for the AutoMQ BYOC Console virtual machine')
param subnetName string = ''

@description('Address prefix for the subnet (CIDR notation)')
param subnetAddressPrefix string = '10.0.0.0/24'

@description('Public IP address configuration: create new, use existing, or none')
@allowed([
  'new'
  'existing'
  'none'
])
param publicIPNewOrExisting string = 'new'

@description('Name of the public IP address (required unless publicIPNewOrExisting is "none")')
param publicIPName string = ''

@description('Resource group name containing the public IP address (defaults to current resource group)')
param publicIPResourceGroup string = resourceGroup().name

@description('Virtual machine size for the AutoMQ BYOC Console')
param vmSize string = 'Standard_D2s_v3'

@description('Administrator username for the virtual machine')
param adminUsername string = 'azureuser'

@description('SSH public key for secure authentication to the virtual machine')
@secure()
param sshPublicKey string

@description('Name of the Azure Storage account for AutoMQ operations data')
param opsStorageAccountName string

@description('Resource group name containing the operations storage account (defaults to current resource group)')
param opsStorageAccountResourceGroup string = resourceGroup().name

@description('Storage account type/SKU for the operations storage account')
param opsStorageAccountType string = 'Standard_LRS'

@description('Storage account kind for the operations storage account')
param opsStorageAccountKind string = 'StorageV2'

@description('Determines whether to create a new storage account or use an existing one')
@allowed([
  'new'
  'existing'
])
param opsStorageAccountIsNew string = 'new'

var imageReference object = {
  id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/AutoMQ/providers/Microsoft.Compute/images/AutoMQ-control-center-Test-0.0.1-SNAPSHOT-0723-03.39-x86_64'
}

module network 'modules/network.bicep' = {
  name: 'network-deployment-${uniqueId}'
  params: {
    location: location
    virtualNetworkNewOrExisting: virtualNetworkNewOrExisting
    virtualNetworkName: virtualNetworkName
    virtualNetworkResourceGroup: virtualNetworkResourceGroup
    subnetName: subnetName
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
    publicIPNewOrExisting: publicIPNewOrExisting
    publicIPName: publicIPName
    publicIPResourceGroup: publicIPResourceGroup
    uniqueId: uniqueId
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage-deployment-${uniqueId}'
  scope: resourceGroup(opsStorageAccountResourceGroup)
  params: {
    opsStorageAccountName: opsStorageAccountName
    opsStorageAccountResourceGroup: opsStorageAccountResourceGroup
    opsStorageAccountType: opsStorageAccountType
    opsStorageAccountKind: opsStorageAccountKind
    opsStorageAccountIsNew: opsStorageAccountIsNew
    uniqueId: uniqueId
  }
}

module vm 'modules/vm.bicep' = {
  name: 'vm-deployment-${uniqueId}'
  params: {
    location: location
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    imageReference: imageReference
    uniqueId: uniqueId
    networkInterfaceId: network.outputs.networkInterfaceId
    opsStorageAccountEndpoint: storage.outputs.opsStorageAccountEndpoint
    vpcResourceGroupName: virtualNetworkResourceGroup
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'rbac-deployment-${uniqueId}'
  scope: subscription()
  params: {
    managedIdentityPrincipalId: vm.outputs.managedIdentityPrincipalId
    uniqueId: uniqueId
  }
}

output automqByocEndpoint string = 'http://${network.outputs.publicIPAddress}:8080'
output automqByocInitialUsername string = 'admin'
@secure()
output automqByocInitialPassword string = vm.outputs.vmId
output automqByocManagedIdentityClientId string = vm.outputs.managedIdentityClientId
