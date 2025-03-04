param serverName string
param databaseName string
param location string
param adminLogin string
@secure()
param adminPassword string

param managedIdentityId string

param sqlAdminIdentityResourceId string
param sqlAdminIdentityPrincipalId string
param deploymentIdentityId string
param deploymentIdentityPrincipalId string
param scriptSubnetId string
param storageSubnetId string
param vnetId string
param clientIpAddress string
param userSID string
param aadUserName string

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    primaryUserAssignedIdentityId: sqlAdminIdentityResourceId
    administrators: {
      administratorType: 'ActiveDirectory'
      login: aadUserName
      azureADOnlyAuthentication: false
      principalType: 'User'
      sid: userSID
      tenantId: subscription().tenantId
    }
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }

  resource database 'databases' = {
    name: databaseName
    location: location
    sku: {
      name: 'Standard'
      tier: 'Standard'
    }
  }
}

// Add a table to the database

resource deploymentScriptStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: substring(replace('${databaseName}deploymentstorage', '-', ''), 0, 24)
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    allowBlobPublicAccess: false
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
      defaultAction: 'Deny'
    }
    accessTier: 'Hot'
  }
}

// take a look to https://johnlokerse.dev/2022/12/04/run-powershell-scripts-with-azure-bicep/
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

resource deploymentMI 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, '-deployment-MI')
  properties: {
    // TODO: use a different identity
    principalId: deploymentIdentityPrincipalId
    roleDefinitionId: storagedatacontributor.id
  }
}

module storagePrivateEndpoint 'privateEndpoint.bicep' = {
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

resource sqlDeploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${databaseName}-deployment-script'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentityId}': {}
    }
  }
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
          id: scriptSubnetId // run the script in a subnet with access to SQL Server
        }
      ]
    }
    environmentVariables: [
      {
        name: 'APPUSERNAME'
        value: managedIdentityId
      }
      {
        name: 'DBNAME'
        value: databaseName
      }
      {
        name: 'DBSERVER'
        value: sqlServer.properties.fullyQualifiedDomainName
      }
      { name: 'TABLENAME', value: 'Values' }
    ]

    scriptContent: '''
wget https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-linux-amd64.tar.bz2
tar x -f sqlcmd-linux-amd64.tar.bz2 -C .

cat <<SCRIPT_END > ./initDb.sql
drop user if exists ${APPUSERNAME}
go
create user ${APPUSERNAME} FROM EXTERNAL PROVIDER
go
alter role db_owner add member ${APPUSERNAME}
go
create table ${TABLENAME} (nvarchar(50) key not null, [value] nvarchar(255),
                           constraint pk_${TABLENAME}_key primary key (nvarchar(50)))
go
SCRIPT_END

echo "Initializing database ${DBNAME} on server ${DBSERVER}"
./sqlcmd -S ${DBSERVER} -d ${DBNAME} -i ./initDb.sql
    '''
  }
}

output endpoint string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlServer::database.name
output serverId string = sqlServer.id
output serverName string = sqlServer.name
