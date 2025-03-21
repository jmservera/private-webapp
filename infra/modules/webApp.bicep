param name string
param location string = resourceGroup().location
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
param identityClientId string = ''
param linuxFxVersion string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'
param healthCheckPath string = '/health'
param alwaysOn bool = true

var baseProperties = {
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: publicNetworkAccess
    httpsOnly: true
    virtualNetworkSubnetId: virtualNetworkSubnetId
    vnetImagePullEnabled: true
  }
}

var baseSiteConfig = {
  linuxFxVersion: linuxFxVersion
  http20Enabled: true
  minTlsVersion: '1.2'
  ftpsState: 'Disabled'
  acrUseManagedIdentityCreds: true // (identityClientId == '') // Only set to true if using system identity
  acrUserManagedIdentityID: identityClientId // Only set if using user assigned identity
  connectionStrings: connectionStrings
  healthCheckPath: healthCheckPath
  alwaysOn: alwaysOn
}

var identity = (identityId == '')
  ? {
      type: 'SystemAssigned'
    }
  : {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${identityId}': {}
      }
    }

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
  properties: union(baseProperties, {
    siteConfig: union(baseSiteConfig, {
      appSettings: concat(appSettings, prodAppSettings)
    })
  })

  identity: identity
}

resource stagingSlot 'Microsoft.Web/sites/slots@2022-09-01' = {
  name: 'staging'
  parent: site
  location: location
  properties: union(baseProperties, {
    siteConfig: union(baseSiteConfig, {
      appSettings: concat(appSettings, stagingAppSettings)
    })
  })
  identity: identity
}

output id string = site.id
output name string = site.name
output url string = 'https://${site.properties.defaultHostName}'
output principalId string = identityId == '' ? site.identity.principalId : ''
output stagingUrl string = 'https://${stagingSlot.properties.defaultHostName}'
output stagingId string = stagingSlot.id
