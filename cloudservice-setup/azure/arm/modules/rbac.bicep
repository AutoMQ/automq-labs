targetScope = 'subscription'

@description('The principal ID of the managed identity.')
param managedIdentityPrincipalId string

@description('A unique identifier for the deployment, used to generate resource names.')
param uniqueId string

var managedIdentityName = 'id-${uniqueId}'

resource id_managedIdentityName_StorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentityName, 'StorageBlobDataOwner')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource id_managedIdentityName_Reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentityName, 'Reader')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource id_managedIdentityName_DNSZoneContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentityName, 'PrivateDNSZoneContributor')
  scope: subscription()
  properties: {
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/b12aa53e-6015-4669-85d0-8515ebb3ae7f'
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource id_managedIdentityName_Contributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, managedIdentityName, 'AzureKubernetesServiceClusterAdminRole')
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8')
    principalId: managedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
