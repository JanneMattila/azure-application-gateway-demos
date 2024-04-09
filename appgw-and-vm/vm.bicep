param name string
param location string
param subnetId string
param username string
@secure()
param password string

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'vm-${name}'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'vm-${name}'
      adminUsername: username
      adminPassword: password
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-azure-edition'
        version: 'latest'
      }
      osDisk: {
        name: 'vm_${name}OSDisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        diskSizeGB: 256
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkApiVersion: '2023-09-01'
      networkInterfaceConfigurations: [
        {
          name: 'nic-vm-${name}'
          properties: {
            ipConfigurations: [
              {
                name: 'ipconfig1'
                properties: {
                  subnet: {
                    id: subnetId
                  }
                  publicIPAddressConfiguration: {
                    name: 'publicipconfig'
                    sku: {
                      name: 'Standard'
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

resource vmInstall 'Microsoft.Compute/virtualMachines/runCommands@2023-07-01' = {
  name: 'vm-install'
  location: location
  parent: vm
  properties: {
    asyncExecution: true
    source: {
      script: '''
        Install-WindowsFeature -name Web-Server -IncludeManagementTools
      '''
    }
  }
}

output vmData object = vm.properties
