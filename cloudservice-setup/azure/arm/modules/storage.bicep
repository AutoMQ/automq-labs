@description('Name of the Azure Storage account for AutoMQ operations data')
param opsStorageAccountName string

@description('Resource group name containing the operations storage account')
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
param opsStorageAccountIsNew string

@description('Name of the blob container for AutoMQ operations data')
param opsContainerName string

// Conditionally create the storage account if it's new
resource newStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = if (opsStorageAccountIsNew == 'new') {
  name: opsStorageAccountName
  location: resourceGroup().location
  sku: {
    name: opsStorageAccountType
  }
  kind: opsStorageAccountKind
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    supportsHttpsTrafficOnly: true
  }
}

// Reference the storage account if it already exists
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (opsStorageAccountIsNew == 'existing') {
  name: opsStorageAccountName
  scope: resourceGroup(opsStorageAccountResourceGroup)
}

// Create blob container for both new and existing storage accounts
// The name format 'parent/child' establishes the dependency.
resource opsBlobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${opsStorageAccountName}/default/${opsContainerName}'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: opsStorageAccountIsNew == 'new' ? [newStorageAccount] : [existingStorageAccount]
}

// The output uses a ternary operator to reference the correct storage account.
output opsStorageAccountEndpoint string = (opsStorageAccountIsNew == 'new' ? newStorageAccount : existingStorageAccount).properties.primaryEndpoints.blob
