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
        New-Item \temp\ -ItemType Directory -Force
        Set-Location \temp\
        Install-WindowsFeature -name Web-Server -IncludeManagementTools
        Invoke-WebRequest "https://nodejs.org/dist/v20.12.1/node-v20.12.1-x64.msi" -OutFile node.msi
        .\node.msi /quiet
        Invoke-WebRequest "https://curl.se/windows/dl-8.7.1_7/curl-8.7.1_7-win64-mingw.zip" -OutFile curl.zip
        Expand-Archive curl.zip -DestinationPath \temp
        New-NetFirewallRule `
         -DisplayName "NodeApp" `
         -LocalPort 8000 `
         -Action Allow `
         -Profile 'Public' `
         -Protocol TCP `
         -Direction Inbound
      '''
    }
  }
}

output vmPublicIP string = publicIP.properties.ipAddress
output vmFQDN string = publicIP.properties.dnsSettings.fqdn
output vmPrivateIP string = nic.properties.ipConfigurations[0].properties.privateIPAddress
