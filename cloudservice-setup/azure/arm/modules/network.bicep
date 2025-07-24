@description('Azure region for deployment')
param location string

@description('Specifies whether the virtual network is new or existing.')
@allowed([
  'new'
  'existing'
])
param virtualNetworkNewOrExisting string

@description('Name of the new or existing Virtual Network.')
param virtualNetworkName string

@description('Name of the resource group where the Virtual Network exists. Defaults to the current resource group.')
param virtualNetworkResourceGroup string

@description('Name of the subnet to deploy the VM into.')
param subnetName string

@description('The address prefix for the new virtual network.')
param virtualNetworkAddressPrefix string

@description('The address prefix for the new subnet.')
param subnetAddressPrefix string

@description('Specifies whether to create a new public IP, use an existing one, or none.')
@allowed([
  'new'
  'existing'
  'none'
])
param publicIPNewOrExisting string

@description('Name of the new or existing public IP address. Only required if publicIPNewOrExisting is not "none".')
param publicIPName string

@description('Name of the resource group where the public IP exists. Defaults to the current resource group. Only required if publicIPNewOrExisting is not "none".')
param publicIPResourceGroup string

@description('A unique identifier for the deployment, used to generate resource names.')
param uniqueId string

var newPublicIpAddressName = (publicIPName != '' && publicIPName != 'NEW-PIP') ? publicIPName : 'pip-${uniqueId}'
var newVnetName = virtualNetworkName != '' ? virtualNetworkName : 'vnet-${uniqueId}'
var newSubnetName = subnetName != '' ? subnetName : 'subnet-${uniqueId}'
var networkInterfaceName = 'nic-${uniqueId}'
var networkSecurityGroupName = 'nsg-${uniqueId}'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-06-01' = if (virtualNetworkNewOrExisting == 'new') {
  name: newVnetName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          serviceEndpoints: [
            { service: 'Microsoft.Storage' }
          ]
        }
      }
    ]
  }
}

resource existingPublicIP 'Microsoft.Network/publicIPAddresses@2023-06-01' existing = if (publicIPNewOrExisting == 'existing' && publicIPName != '' && publicIPResourceGroup != '') {
  name: publicIPName
  scope: resourceGroup(publicIPResourceGroup)
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-06-01' = {
  name: networkSecurityGroupName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowHTTP8080'
        properties: {
          priority: 1001
          protocol: 'TCP'
          access: 'Allow'
          direction: 'Inbound'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8080'
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-06-01' = if (publicIPNewOrExisting == 'new') {
  name: newPublicIpAddressName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

var subnetId = resourceId(
  virtualNetworkNewOrExisting == 'new' ? resourceGroup().name : virtualNetworkResourceGroup,
  'Microsoft.Network/virtualNetworks/subnets',
  virtualNetworkName,
  newSubnetName
)

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-06-01' = {
  name: networkInterfaceName
  location: location
  tags: {
    automqVendor: 'automq'
    automqDeploymentID: uniqueId
  }
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig-${uniqueId}'
        properties: union({
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
        },
        (publicIPNewOrExisting == 'new') ? {
          publicIPAddress: {
            id: publicIP.id
          }
        } : (publicIPNewOrExisting == 'existing' && publicIPName != '' && publicIPResourceGroup != '') ? {
          publicIPAddress: {
            id: existingPublicIP.id
          }
        } : {})
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

output subnetId string = subnetId
output networkInterfaceId string = networkInterface.id
output publicIPAddress string = (publicIPNewOrExisting == 'new' && publicIPName != '' ? publicIP.properties.ipAddress : publicIPNewOrExisting == 'existing' && publicIPName != '' && publicIPResourceGroup != '' ? existingPublicIP.properties.ipAddress : networkInterface.properties.ipConfigurations[0].properties.privateIPAddress)
