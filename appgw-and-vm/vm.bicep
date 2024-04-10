param name string
param location string
param subnetId string
param username string
@secure()
param password string

resource publicIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: 'pip-vm'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: name
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2020-04-01' = {
  name: 'nic-vm'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: name
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: name
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
      networkInterfaces: [
        {
          id: nic.id
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
    protectedParameters: [
      {
        name: 'password'
        value: password
      }
    ]
    source: {
      script: '''
        Install-WindowsFeature -name Web-Server -IncludeManagementTools
      '''
    }
  }
}

output vmPublicIP string = publicIP.properties.ipAddress
output vmFQDN string = publicIP.properties.dnsSettings.fqdn
output vmPrivateIP string = nic.properties.ipConfigurations[0].properties.privateIPAddress