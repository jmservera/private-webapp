param location string
param ghRunnerName string
param repo_name string
param repo_owner string
param githubPAT string
param adminUserName string
param identityClientId string
param branch string = 'main'

resource ghRunnerScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  name: '${ghRunnerName}/ghRunnerScriptExtension'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {
      fileUris: [
        uri(
          'https://raw.githubusercontent.com',
          '${repo_owner}/${repo_name}/refs/heads/${branch}/scripts/install-packages.sh'
        )
      ]
    }
    protectedSettings: {
      commandToExecute: 'USER=${adminUserName} REPO_OWNER=${repo_owner} REPO_NAME=${repo_name} GITHUB_PAT="${githubPAT}" bash install-packages.sh'
      managedIdentity: { clientId: identityClientId }
    }
  }
}

output ghRunnnerExtensionResult object = ghRunnerScriptExtension.properties.instanceView
