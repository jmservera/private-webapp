param ghRunnerExists bool
param location string = resourceGroup().location
param namePrefix string = 'appDemo'
param sqlAdminLogin string = 'sqladmin'
@secure()
param sqlAdminPassword string
param tags object = {}
@description('Id of the user or app to assign application roles')
param principalId string
param ghRunnerDefinition object

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Virtual network with two subnets
module vnet './modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    namePrefix: namePrefix
    location: location
  }
}

// Frontend web app with public access
module frontEndApp './modules/webApp.bicep' = {
  name: 'frontEndApp'
  params: {
    name: '${namePrefix}-frontend'
    location: location
    planName: '${namePrefix}-frontPlan'
    skuName: 'S1'
    skuTier: 'Standard'
    publicNetworkAccess: 'Enabled'
  }
}

// Backend web app with private access
module backEndApp './modules/webApp.bicep' = {
  name: 'backEndApp'
  params: {
    name: '${namePrefix}-backend'
    location: location
    planName: '${namePrefix}-backPlan'
    skuName: 'S1'
    skuTier: 'Standard'
    publicNetworkAccess: 'Disabled'
  }
}

// SQL Database
module sqlDb './modules/sqlDatabase.bicep' = {
  name: 'sqlDb'
  params: {
    serverName: '${namePrefix}-sqlserver'
    databaseName: '${namePrefix}-db'
    location: location
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
  }
}

// Private endpoint for backend
module backEndPrivateEndpoint './modules/privateEndpoint.bicep' = {
  name: 'backEndPrivateEndpoint'
  params: {
    name: '${namePrefix}-backend'
    location: location
    vnetId: vnet.outputs.vnetId
    subnetId: vnet.outputs.appSubnetId
    privateLinkServiceId: backEndApp.outputs.id
    targetSubResource: 'sites'
  }
}

// Private endpoint for SQL
module sqlPrivateEndpoint './modules/privateEndpoint.bicep' = {
  name: 'sqlPrivateEndpoint'
  params: {
    name: '${namePrefix}-sql'
    location: location
    subnetId: vnet.outputs.privateSubnetId
    vnetId: vnet.outputs.vnetId
    privateLinkServiceId: sqlDb.outputs.serverId
    targetSubResource: 'sqlServer'
  }
}

module ghRunnerAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'ghappidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}gh-${resourceToken}'
    location: location
  }
}
// Container registry
module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = {
  name: 'registry'
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    acrAdminUserEnabled: true
    tags: tags
    publicNetworkAccess: 'Enabled'
    roleAssignments: [
      {
        principalId: ghRunnerAppIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: subscriptionResourceId(
          'Microsoft.Authorization/roleDefinitions',
          '7f951dda-4ed3-4680-a7ca-43fe172d538d'
        )
      }
    ]
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.6.1' = {
  name: 'keyvault'
  params: {
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    enableRbacAuthorization: false
    accessPolicies: [
      {
        objectId: principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
      {
        objectId: ghRunnerAppIdentity.outputs.principalId
        permissions: {
          secrets: ['get', 'list']
        }
      }
    ]
    secrets: []
  }
}

module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.4.5' = {
  name: 'container-apps-environment'
  params: {
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    zoneRedundant: false
  }
}

module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
  }
}

module ghRunnerFetchLatestImage './modules/fetch-container-image.bicep' = {
  name: 'ghrunner-fetch-image'
  params: {
    exists: ghRunnerExists
    name: 'ghrunner'
  }
}

var ghRunnerAppSettingsArray = filter(array(ghRunnerDefinition.settings), i => i.name != '')
var ghRunnerSecrets = map(filter(ghRunnerAppSettingsArray, i => i.?secret != null), i => {
  name: i.name
  value: i.value
  secretRef: i.?secretRef ?? take(replace(replace(toLower(i.name), '_', '-'), '.', '-'), 32)
})
var ghRunnerEnv = map(filter(ghRunnerAppSettingsArray, i => i.?secret == null), i => {
  name: i.name
  value: i.value
})

module ghRunner 'br/public:avm/res/app/container-app:0.8.0' = {
  name: 'ghrunner'
  params: {
    name: 'ghrunner'
    ingressTargetPort: 5001
    scaleMinReplicas: 1
    scaleMaxReplicas: 10
    secrets: {
      secureList: union(
        [],
        map(ghRunnerSecrets, secret => {
          name: secret.secretRef
          value: secret.value
        })
      )
    }
    containers: [
      {
        image: ghRunnerFetchLatestImage.outputs.?containers[?0].?image ?? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        name: 'main'
        resources: {
          cpu: json('0.5')
          memory: '1.0Gi'
        }
        env: union(
          [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: monitoring.outputs.applicationInsightsConnectionString
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: ghRunnerAppIdentity.outputs.clientId
            }
            {
              name: 'PORT'
              value: '5001'
            }
          ],
          ghRunnerEnv,
          map(ghRunnerSecrets, secret => {
            name: secret.name
            secretRef: secret.secretRef
          })
        )
      }
    ]
    managedIdentities: {
      systemAssigned: false
      userAssignedResourceIds: [ghRunnerAppIdentity.outputs.resourceId]
    }
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: ghRunnerAppIdentity.outputs.resourceId
      }
    ]
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    location: location
    tags: union(tags, { 'azd-service-name': 'ghRunner' })
  }
}

//https://learn.microsoft.com/en-us/azure/container-apps/tutorial-ci-cd-runners-jobs?tabs=bash&pivots=container-apps-jobs-self-hosted-ci-cd-github-actions

// module containerApp 'modules/containerApp.bicep' = {name: 'containerApp'
//   params: {
//     name: '${namePrefix}-container'
//     location: location
//     containerImage:
//   }
// }

// Output important values
output frontendUrl string = frontEndApp.outputs.url
output frontendId string = frontEndApp.outputs.id
output backendId string = backEndApp.outputs.id
output sqlServerId string = sqlDb.outputs.serverId

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.uri
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_RESOURCE_GHRUNNER_ID string = ghRunner.outputs.resourceId
