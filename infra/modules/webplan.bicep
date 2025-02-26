param location string = resourceGroup().location
param name string

param sku object = {
  name: 'S1'
  tier: 'Standard'
}

resource plan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: name
  location: location
  sku: sku
  kind: 'linux'
  properties: {
    reserved: true
  }
}

output id string = plan.id
