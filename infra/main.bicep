targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

param publicKey string
param ghRunnerDefinition object
param repo_owner string
param repo_name string

@minLength(1)
@description('Primary location for all resources')
param location string
@description('Id of the user or app to assign application roles')
param principalId string

param sqlAdminLogin string = 'sqladmin'
@secure()
param sqlAdminPassword string

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module resources './resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    namePrefix: environmentName
    sqlAdminLogin: sqlAdminLogin
    sqlAdminPassword: sqlAdminPassword
    tags: tags
    location: location
    principalId: principalId
    ghRunnerDefinition: ghRunnerDefinition
    repo_name: repo_name
    repo_owner: repo_owner
    publicKey: publicKey
  }
}

output AZURE_KEY_VAULT_ENDPOINT string = resources.outputs.AZURE_KEY_VAULT_ENDPOINT
output AZURE_KEY_VAULT_NAME string = resources.outputs.AZURE_KEY_VAULT_NAME
output AZURE_RESOURCE_GHRUNNER_ID string = resources.outputs.AZURE_RESOURCE_GHRUNNER_ID
