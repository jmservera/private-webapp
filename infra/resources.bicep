param location string = resourceGroup().location
param namePrefix string = 'appDemo'
param sqlAdminLogin string = 'sqladmin'
@secure()
param sqlAdminPassword string
param tags object = {}
@description('Id of the user or app to assign application roles')
param principalId string
param ghRunnerDefinition object
param production bool = false

@secure()
param publicKey string

param repo_name string
param repo_owner string
@secure()
param githubPat string

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
// // Container registry
// module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = {
//   name: 'registry'
//   params: {
//     name: '${abbrs.containerRegistryRegistries}${resourceToken}'
//     location: location
//     acrAdminUserEnabled: true
//     tags: tags
//     publicNetworkAccess: 'Enabled'
//     roleAssignments: [
//       {
//         principalId: ghRunnerAppIdentity.outputs.principalId
//         principalType: 'ServicePrincipal'
//         roleDefinitionIdOrName: subscriptionResourceId(
//           'Microsoft.Authorization/roleDefinitions',
//           '7f951dda-4ed3-4680-a7ca-43fe172d538d'
//         )
//       }
//     ]
//   }
// }

// module keyVault 'br/public:avm/res/key-vault/vault:0.6.1' = {
//   name: 'keyvault'
//   params: {
//     name: '${abbrs.keyVaultVaults}${resourceToken}'
//     location: location
//     tags: tags
//     enableRbacAuthorization: false
//     enablePurgeProtection: production
//     enableSoftDelete: production
//     accessPolicies: [
//       {
//         objectId: principalId
//         permissions: {
//           secrets: ['get', 'list', 'set']
//         }
//       }
//       {
//         objectId: ghRunnerAppIdentity.outputs.principalId
//         permissions: {
//           secrets: ['get', 'list']
//         }
//       }
//     ]
//     secrets: []
//   }
// }

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

module ghRunner 'br/public:avm/res/compute/virtual-machine:0.12.1' = {
  name: 'virtualMachineDeployment'
  params: {
    // Required parameters
    adminUsername: 'localAdminUser'
    imageReference: {
      offer: '0001-com-ubuntu-server-jammy'
      publisher: 'Canonical'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
    name: 'ghRunner'
    encryptionAtHost: false
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            pipConfiguration: {
              name: 'pip-01'
            }
            subnetResourceId: vnet.outputs.appSubnetId
          }
        ]
        nicSuffix: '-nic-01'
      }
    ]
    osDisk: {
      caching: 'ReadWrite'
      diskSizeGB: 128
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    osType: 'Linux'
    vmSize: 'Standard_D2s_v3'
    zone: 0
    // Non-required parameters
    disablePasswordAuthentication: true
    location: location
    publicKeys: [
      {
        keyData: publicKey
        path: '/home/localAdminUser/.ssh/authorized_keys'
      }
    ]
    extensionCustomScriptConfig: {
      enabled: true
      settings: {
        commandToExecute: 'REPO_OWNER=${repo_owner} REPO_NAME=${repo_name} GITHUB_PAT=${githubPat} bash install-packages.sh'
      }
      fileData: [
        {
          uri: 'https://raw.githubusercontent.com/jmservera/private-webapp/refs/heads/main/scripts/install-packages.sh'
        }
      ]
    }
    extensionCustomScriptProtectedSetting: {
      commandToExecute: 'bash install-packages.sh'
    }
  }
}

// Output important values
output frontendUrl string = frontEndApp.outputs.url
output frontendId string = frontEndApp.outputs.id
output backendId string = backEndApp.outputs.id
output sqlServerId string = sqlDb.outputs.serverId

// output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.uri
// output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_RESOURCE_GHRUNNER_ID string = ghRunner.outputs.resourceId
