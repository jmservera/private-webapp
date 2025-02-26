param name string
param location string
param planName string
param skuName string = 'S1'
param skuTier string = 'Standard'
param publicNetworkAccess string = 'Enabled'

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: planName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
}

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    publicNetworkAccess: publicNetworkAccess
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output id string = webApp.id
output url string = 'https://${webApp.properties.defaultHostName}'
output name string = webApp.name
