param serverName string
param databaseName string
param location string
param adminLogin string
@secure()
param adminPassword string

param deploymentIdentityClientId string
param deploymentIdentityResourceId string
param deploymentIdentityPrincipalId string
param deploymentIdentityName string

param appIdentityName string
param appIdentityClientId string

param scriptRunnerSubnetId string
param storageSubnetId string
param vnetId string
param clientIpAddress string

@description('Set to false to make the critical resources public. Use this only for testing.')
param private bool = true

param sku object = {
  name: 'Standard'
  tier: 'Standard'
}

resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    administrators: {
      administratorType: 'ActiveDirectory'
      login: deploymentIdentityName
      azureADOnlyAuthentication: false
      principalType: 'Application'
      sid: deploymentIdentityClientId
      tenantId: subscription().tenantId
    }
    publicNetworkAccess: private ? 'Disabled' : 'Enabled'
    minimalTlsVersion: '1.2'
  }

  resource database 'databases' = {
    name: databaseName
    location: location
    sku: sku
  }
  resource firewallRulesAzure 'firewallRules' = if (!private) {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
  resource firewallRulesClient 'firewallRules' = if (!private) {
    name: 'AllowClientIp'
    properties: {
      startIpAddress: clientIpAddress
      endIpAddress: clientIpAddress
    }
  }
}

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

// create private endpoints for the storage account
module storagePrivateEndpoint 'privateEndpoint.bicep' = if (private) {
  name: '${databaseName}-deployment-storage-pe'
  params: {
    location: location
    name: '${databaseName}-deployment-storage-pe'
    privateLinkServiceId: deploymentScriptStorage.id
    subnetId: storageSubnetId
    targetSubResource: 'file'
    vnetId: vnetId
  }
}

// create private endpoints for the SQL Server
module dbPrivateEndpoint 'privateEndpoint.bicep' = if (private) {
  name: '${databaseName}-sql-server-pe'
  params: {
    location: location
    name: '${databaseName}-sql-server-pe'
    privateLinkServiceId: sqlServer.id
    subnetId: storageSubnetId
    targetSubResource: 'sqlServer'
    vnetId: vnetId
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
        dbPrivateEndpoint
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
      { name: 'DBNAME', value: sqlServer::database.name }
      { name: 'DBSERVER', value: sqlServer.properties.fullyQualifiedDomainName }
      { name: 'TABLENAME', value: 'Value_Store' }
      { name: 'APPIDENTITYNAME', value: appIdentityName }
      { name: 'APPIDENTITYID', value: appIdentityClientId }
    ]
    scriptContent: loadTextContent('../../scripts/create-sql-user.sh')
  }
}

output endpoint string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlServer::database.name
output serverId string = sqlServer.id
output serverName string = sqlServer.name
