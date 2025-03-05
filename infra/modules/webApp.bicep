param name string
param location string
param planName string
param skuName string = 'S1'
param skuTier string = 'Standard'
param publicNetworkAccess string = 'Enabled'
param virtualNetworkSubnetId string = ''
param appSettings array = []
param connectionStrings array = []
param identityId string = ''

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    reserved: true // Required for Linux
  }
}

resource site 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: publicNetworkAccess
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: appSettings
      connectionStrings: connectionStrings
      healthCheckPath: '/health'
    }
    virtualNetworkSubnetId: virtualNetworkSubnetId
  }
  identity: (identityId == '')
    ? {
        type: 'SystemAssigned'
      }
    : {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${identityId}': {}
        }
      }
}

output id string = site.id
output name string = site.name
output url string = 'https://${site.properties.defaultHostName}'
output principalId string = identityId==''? site.identity.principalId : ''
