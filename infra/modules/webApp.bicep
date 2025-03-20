param name string
param location string
param planName string
param skuName string = 'S1'
param skuTier string = 'Standard'
param publicNetworkAccess string = 'Enabled'
param virtualNetworkSubnetId string = ''
param appSettings array = []
param prodAppSettings array = []
param stagingAppSettings array = []
param connectionStrings array = []
param identityId string = ''
param linuxFxVersion string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'

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
      linuxFxVersion: linuxFxVersion
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat(appSettings, prodAppSettings)
      connectionStrings: connectionStrings
      healthCheckPath: '/health'
      alwaysOn: true
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

resource stagingSlot 'Microsoft.Web/sites/slots@2022-09-01' = {
  name: 'staging'
  parent: site
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: publicNetworkAccess
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: concat(appSettings, stagingAppSettings)
      connectionStrings: connectionStrings
      healthCheckPath: '/health'
      alwaysOn: true
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
output principalId string = identityId == '' ? site.identity.principalId : ''
output stagingUrl string = 'https://${stagingSlot.properties.defaultHostName}'
output stagingId string = stagingSlot.id
