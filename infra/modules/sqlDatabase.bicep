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

resource sqlServer 'Microsoft.Sql/servers@2022-05-01-preview' = {
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
  }
}

// create private endpoints for the storage account
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

// create private endpoints for the SQL Server
module dbPrivateEndpoint 'privateEndpoint.bicep' = {
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
      {
        name: 'CLIENTID'
        value: deploymentIdentityClientId
      }
      {
        name: 'DBNAME'
        value: databaseName
      }
      {
        name: 'DBSERVER'
        value: sqlServer.properties.fullyQualifiedDomainName
      }
      { name: 'TABLENAME', value: 'Value_Store' }
      { name: 'APPIDENTITYNAME', value: appIdentityName }
      { name: 'APPIDENTITYID', value: appIdentityClientId }
    ]

    scriptContent: '''
generate_sid() {
    # Remove hyphens and extract parts in correct order
    guid_clean=$(echo "$1" | tr -d '-')
    
    # Extract and reorder parts directly
    p1=$(expr substr "$guid_clean" 7 2)$(expr substr "$guid_clean" 5 2)$(expr substr "$guid_clean" 3 2)$(expr substr "$guid_clean" 1 2)
    p2=$(expr substr "$guid_clean" 11 2)$(expr substr "$guid_clean" 9 2)
    p3=$(expr substr "$guid_clean" 15 2)$(expr substr "$guid_clean" 13 2)
    p4=$(expr substr "$guid_clean" 17 16)
    
    # Combine, convert to uppercase and add prefix
    echo "0x$(echo "${p1}${p2}${p3}${p4}" | tr '[:lower:]' '[:upper:]')"
}

#create user [${APPIDENTITYNAME}] FROM EXTERNAL PROVIDER

# https://stackoverflow.com/questions/76995900/how-to-grant-a-managed-identity-permissions-to-an-azure-sql-database-using-iac
# appIdentityName$appId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' (this is the clientid)
# $sid = "0x" + [System.BitConverter]::ToString(([guid]$appId).ToByteArray()).Replace("-", "")

SID=$(generate_sid "${APPIDENTITYID}")

wget https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-linux-amd64.tar.bz2
tar x -f sqlcmd-linux-amd64.tar.bz2 -C .

# before running this the MI needs to have Directory Readers role in Entra

cat <<SCRIPT_END > ./initDb.sql
drop user if exists [${APPIDENTITYNAME}]
go
CREATE USER [${APPIDENTITYNAME}] WITH DEFAULT_SCHEMA=[dbo], SID = $SID, TYPE = E;
go
-- alter role db_owner add member [${APPIDENTITYNAME}]
-- go
create table ${TABLENAME} ([key] nvarchar(50) PRIMARY KEY, [stored_value] nvarchar(255))
go
SCRIPT_END

echo "Initializing database ${DBNAME} on server ${DBSERVER}"
./sqlcmd -S "${DBSERVER}" -d "${DBNAME}" --authentication-method ActiveDirectoryManagedIdentity -U "${CLIENTID}" -i ./initDb.sql
    '''
  }
}

output endpoint string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlServer::database.name
output serverId string = sqlServer.id
output serverName string = sqlServer.name
