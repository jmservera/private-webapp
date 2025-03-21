param location string = resourceGroup().location
param namePrefix string = 'appDemo'
param sqlAdminLogin string = 'sqladmin'
@secure()
param sqlAdminPassword string
param tags object = {}
@description('GH Runner VM admin password if needed, you may leave it empty if using key authentication')
@secure()
param adminPassword string = ''
@description('GH Runner VM administrator name')
param adminUserName string = 'localAdminUser'

@description('Public Key for GH Runner VM authentication')
@secure()
param publicKey string = ''

param repo_name string
param repo_owner string
@secure()
param githubPAT string
@description('The IP address of the current client that is running the azd up command, used for setting firewall rules for the storage account.')
param clientIpAddress string

param ValuesTableName string = 'Value_Store'

param frontendContainerImage string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'
param backendContainerImage string = 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Virtual network with two subnets
module vnet './modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    namePrefix: namePrefix
  }
}

// Frontend web app with public access
module frontEndApp './modules/webApp.bicep' = {
  name: 'frontEndApp'
  params: {
    name: '${namePrefix}-frontend'
    planName: '${namePrefix}-frontPlan'
    skuName: 'S1'
    skuTier: 'Standard'
    publicNetworkAccess: 'Enabled'
    linuxFxVersion: frontendContainerImage
    virtualNetworkSubnetId: vnet.outputs.appSubnetId
    appSettings: [
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: monitoring.outputs.applicationInsightsConnectionString
      }
    ]
    prodAppSettings: [
      {
        name: 'BACKEND'
        value: backEndApp.outputs.url
        slotSetting: true
      }
    ]
    stagingAppSettings: [
      {
        name: 'BACKEND'
        value: backEndApp.outputs.stagingUrl
        slotSetting: true
      }
    ]
  }
}

module backendAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'backendAppIdentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}backend-${resourceToken}'
  }
}

// Backend web app with private access
module backEndApp './modules/webApp.bicep' = {
  name: 'backEndApp'
  params: {
    name: '${namePrefix}-backend'
    planName: '${namePrefix}-backPlan'
    skuName: 'S1'
    skuTier: 'Standard'
    publicNetworkAccess: 'Disabled'
    linuxFxVersion: backendContainerImage
    virtualNetworkSubnetId: vnet.outputs.appSubnetId
    appSettings: [
      {
        name: 'TableName'
        value: ValuesTableName
      }
      {
        name: 'ConnectionString'
        value: 'Driver={ODBC Driver 18 for SQL Server};Server=tcp:${sqlDb.outputs.serverName}${environment().suffixes.sqlServerHostname},1433;Database=${sqlDb.outputs.databaseName};UID=${backendAppIdentity.outputs.clientId};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;Authentication=ActiveDirectoryMsi;'
      }
      {
        name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
        value: '~3'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: monitoring.outputs.applicationInsightsConnectionString
      }
    ]
    identityId: backendAppIdentity.outputs.resourceId
    identityClientId: backendAppIdentity.outputs.clientId
  }
}

// SQL Database
module sqlDb './modules/sqlDatabase.bicep' = {
  name: 'sqlDb'
  params: {
    serverName: '${namePrefix}-sqlserver'
    databaseName: '${namePrefix}-db'
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
    deploymentIdentityName: ghRunnerAppIdentity.outputs.name
    deploymentIdentityClientId: ghRunnerAppIdentity.outputs.clientId
    subnetId: vnet.outputs.privateSubnetId
    vnetId: vnet.outputs.vnetId
  }
}

module dbScript 'modules/sqlScript.bicep' = {
  name: 'dbScript'
  params: {
    sqlServerEndpoint: sqlDb.outputs.endpoint
    databaseName: sqlDb.outputs.databaseName
    scriptRunnerSubnetId: vnet.outputs.ciSubnetId
    vnetId: vnet.outputs.vnetId
    clientIpAddress: clientIpAddress
    deploymentIdentityResourceId: ghRunnerAppIdentity.outputs.resourceId
    deploymentIdentityPrincipalId: ghRunnerAppIdentity.outputs.principalId
    appIdentityName: backendAppIdentity.outputs.name
    appIdentityClientId: backendAppIdentity.outputs.clientId
    deploymentIdentityClientId: ghRunnerAppIdentity.outputs.clientId
    subnetId: vnet.outputs.privateSubnetId
  }
}

// Add permissions to SQL Server for ghRunner identity
module ghRunnerSqlContributor 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'ghRunnerSqlContributor'
  params: {
    principalId: ghRunnerAppIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    resourceId: sqlDb.outputs.serverId
  }
}

resource ghRunnerResourceGroupContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, 'ghRunnerResourceGroupContributor')
  properties: {
    // delegatedManagedIdentityResourceId: ghRunnerAppIdentity.outputs.resourceId
    principalId: ghRunnerAppIdentity.outputs.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalType: 'ServicePrincipal'
  }
}

resource ghRunnerWebSiteContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, 'ghRunnerWebSiteContributor')
  properties: {
    principalId: ghRunnerAppIdentity.outputs.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772') // WebSite Contributor role
    // as the Managed Identity was just created, it may take a few minutes to be replicated to all regions
    // so we need to specify the principal type as 'ServicePrincipal', otherwise the assignment may fail if the identity is not yet available
    principalType: 'ServicePrincipal'
  }
}

// Add role assignments for Web Apps to access Container Registry
module frontendWebAppAcrPull 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'frontendWebAppAcrPull'
  params: {
    principalId: frontEndApp.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    resourceId: containerRegistry.outputs.resourceId
  }
}

module backendWebAppAcrPull 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  name: 'backendWebAppAcrPull'
  params: {
    principalId: backendAppIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull role
    resourceId: containerRegistry.outputs.resourceId
  }
}

// Private endpoint for backend
module backEndPrivateEndpoint './modules/privateEndpoint.bicep' = {
  name: 'backEndPrivateEndpoint'
  params: {
    name: '${namePrefix}-backend'
    vnetId: vnet.outputs.vnetId
    subnetId: vnet.outputs.privateSubnetId
    privateLinkServiceId: backEndApp.outputs.id
    targetSubResource: 'sites'
  }
}

module backEndSlotPrivateEndpoint './modules/privateEndpoint.bicep' = {
  name: 'backEndSlotPrivateEndpoint'
  params: {
    name: '${namePrefix}-backend-staging'
    vnetId: vnet.outputs.vnetId
    subnetId: vnet.outputs.privateSubnetId
    privateLinkServiceId: backEndApp.outputs.id // same as the main site, not the staging slot
    targetSubResource: 'sites-staging' // use the slot name appended to sites-
    zoneName: backEndPrivateEndpoint.outputs.zoneName
  }
}

module ghRunnerAppIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'ghappidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}gh-${resourceToken}'
  }
}

// Container registry
module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = {
  name: 'registry'
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    acrSku: 'Premium'
    acrAdminUserEnabled: true
    tags: tags
    publicNetworkAccess: 'Disabled'
    roleAssignments: [
      {
        principalId: ghRunnerAppIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: resourceId(
          'Microsoft.Authorization/roleDefinitions',
          '7f951dda-4ed3-4680-a7ca-43fe172d538d'
        )
      }
    ]
  }
}

module containerRegistryPrivateEndpoint 'modules/privateEndpoint.bicep' = {
  name: 'containerRegistryPrivateEndpoint'
  params: {
    name: '${namePrefix}-acr'
    vnetId: vnet.outputs.vnetId
    subnetId: vnet.outputs.privateSubnetId
    privateLinkServiceId: containerRegistry.outputs.resourceId
    targetSubResource: 'registry'
  }
}

module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    tags: tags
  }
}

module ghRunner 'br/public:avm/res/compute/virtual-machine:0.12.1' = {
  name: 'virtualMachineDeployment'
  params: {
    // Required parameters
    adminUsername: adminUserName
    imageReference: {
      offer: '0001-com-ubuntu-server-jammy'
      publisher: 'Canonical'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
    name: 'ghRunner'
    managedIdentities: {
      userAssignedResourceIds: [
        ghRunnerAppIdentity.outputs.resourceId
      ]
    }
    encryptionAtHost: false
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig01'
            subnetResourceId: vnet.outputs.vmSubnetId
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
    bootDiagnostics: true
    zone: 0
    // Non-required parameters
    disablePasswordAuthentication: empty(adminPassword) ? true : false
    adminPassword: adminPassword
    publicKeys: empty(publicKey)
      ? null
      : [
          {
            keyData: publicKey
            path: '/home/localAdminUser/.ssh/authorized_keys'
          }
        ]
  }
}

module ghRunnerScriptExtension './modules/ghScript.bicep' = {
  name: 'ghRunnerScriptExtension'
  params: {
    ghRunnerName: ghRunner.outputs.name
    repo_name: repo_name
    repo_owner: repo_owner
    githubPAT: githubPAT
    adminUserName: adminUserName
    identityClientId: ghRunnerAppIdentity.outputs.clientId
  }
}

// Output important values
output frontendUrl string = frontEndApp.outputs.url
output frontendId string = frontEndApp.outputs.id
output backendId string = backEndApp.outputs.id
output sqlServerId string = sqlDb.outputs.serverId

output AZURE_RESOURCE_GHRUNNER_ID string = ghRunner.outputs.resourceId
output acrName string = containerRegistry.outputs.name
output acrLoginServer string = containerRegistry.outputs.loginServer
output sqlServerEndpoint string = sqlDb.outputs.endpoint
output sqlDatabaseName string = sqlDb.outputs.databaseName
output AZURE_RESOURCE_GHRUNNER_NAME string = ghRunner.outputs.name
