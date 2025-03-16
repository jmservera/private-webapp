param location string
param ghRunnerName string
param repo_name string
param repo_owner string
param githubPAT string
param adminUserName string
param identityClientId string

resource ghRunnerScriptExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  name: '${ghRunnerName}/ghRunnerScriptExtension'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    settings: {   
      //https://raw.githubusercontent.com/jmservera/private-webapp/refs/heads/jmservera/bicep-cleanup/scripts/install-packages.sh
      fileUris: [uri('https://raw.githubusercontent.com','jmservera/private-webapp/refs/heads/jmservera/bicep-cleanup/scripts/install-packages.sh')]
    }
    protectedSettings:{
        commandToExecute: 'REPO_OWNER=${repo_owner} REPO_NAME=${repo_name} GITHUB_PAT="${githubPAT}" bash install-packages.sh'
        managedIdentity: { clientId: identityClientId }
      }
  }
}

output ghRunnnerExtensionResult object = ghRunnerScriptExtension.properties.instanceView
