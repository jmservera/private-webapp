param vmName string
param location string

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: vmName
}

resource linuxVMExtensions 'Microsoft.Compute/virtualMachines/extensions@2019-07-01' = {
  parent: vm
  name: '${vmName}-script'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: loadFileAsBase64('../../scripts/install-packages.sh')
    }
  }
}
