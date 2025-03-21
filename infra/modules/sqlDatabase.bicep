param serverName string
param databaseName string
param location string = resourceGroup().location
param adminLogin string
@secure()
param adminPassword string
param deploymentIdentityName string
param deploymentIdentityClientId string

param subnetId string
param vnetId string

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
    publicNetworkAccess: 'Disabled'
    minimalTlsVersion: '1.2'
  }

  resource database 'databases' = {
    name: databaseName
    location: location
    sku: sku
  }
}

// create private endpoints for the SQL Server
module dbPrivateEndpoint 'privateEndpoint.bicep' = {
  name: '${databaseName}-sql-server-pe'
  params: {
    location: location
    name: '${databaseName}-sql-server-pe'
    privateLinkServiceId: sqlServer.id
    subnetId: subnetId
    targetSubResource: 'sqlServer'
    vnetId: vnetId
  }
}

output endpoint string = sqlServer.properties.fullyQualifiedDomainName
output databaseName string = sqlServer::database.name
output serverId string = sqlServer.id
output serverName string = sqlServer.name
