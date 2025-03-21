param databaseName string
param location string = resourceGroup().location
param clientIpAddress string
param deploymentIdentityPrincipalId string
param deploymentIdentityClientId string
param deploymentIdentityResourceId string
param scriptRunnerSubnetId string
param subnetId string
param vnetId string
param appIdentityName string
param appIdentityClientId string
param sqlServerEndpoint string

@description('Set to false to make the critical resources public. Use this only for testing.')
param private bool = true

resource deploymentScriptStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: substring(replace('${databaseName}deploymentstorage', '-', ''), 0, 24)
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      resourceAccessRules: []
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [
        {
          value: clientIpAddress
          action: 'Allow'
        }
      ]
      defaultAction: 'Allow'
    }
    accessTier: 'Hot'
  }
}

// create private endpoints for the storage account
module storagePrivateEndpoint 'privateEndpoint.bicep' = if (private) {
  name: '${databaseName}-deployment-storage-pe'
  params: {
    location: location
    name: '${databaseName}-deployment-storage-pe'
    privateLinkServiceId: deploymentScriptStorage.id
    subnetId: subnetId
    targetSubResource: 'file'
    vnetId: vnetId
  }
}

// add needed role definition based on
// https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-script-template#configure-the-minimum-permissions
resource storagedatacontributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(deploymentScriptStorage.name, 'blob-data-contributor-role')
  properties: {
    roleName: '${deploymentScriptStorage.name}-blob-data-contributor-role'
    description: 'Deployment script role definition for storage, containers and deployments'
    assignableScopes: [resourceGroup().id]
    permissions: [
      {
        actions: [
          'Microsoft.Storage/storageAccounts/*'
          'Microsoft.ContainerInstance/containerGroups/*'
          'Microsoft.Resources/deployments/*'
          'Microsoft.Resources/deploymentScripts/*'
        ]
        // NOT DOCUMENTED BUT REQUIRED
        dataActions: [
          'Microsoft.Storage/storageAccounts/fileServices/*'
        ]
      }
    ]
  }
}

// assign the role to the deployment identity
resource deploymentMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, deploymentIdentityPrincipalId, 'deployment-role-assignment')
  properties: {
    principalId: deploymentIdentityPrincipalId
    roleDefinitionId: storagedatacontributor.id
    principalType: 'ServicePrincipal'
  }
}

resource sqlDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${databaseName}-deployment-script'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentityResourceId}': {}
    }
  }
  dependsOn: private
    ? [
        storagePrivateEndpoint
        deploymentMI
      ]
    : [
        deploymentMI
      ]
  properties: {
    azCliVersion: '2.37.0'
    retentionInterval: 'PT1H' // Retain the script resource for 1 hour after it ends running
    timeout: 'PT5M' // Five minutes
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {
      storageAccountName: deploymentScriptStorage.name
    }
    containerSettings: {
      subnetIds: [
        {
          id: scriptRunnerSubnetId // run the script in a subnet with access to SQL Server
        }
      ]
    }
    environmentVariables: [
      { name: 'CLIENTID', value: deploymentIdentityClientId }
      { name: 'DBNAME', value: databaseName }
      { name: 'DBSERVER', value: sqlServerEndpoint }
      { name: 'TABLENAME', value: 'Value_Store' }
      { name: 'APPIDENTITYNAME', value: appIdentityName }
      { name: 'APPIDENTITYID', value: appIdentityClientId }
    ]
    scriptContent: loadTextContent('../../scripts/create-sql-user.sh')
  }
}
