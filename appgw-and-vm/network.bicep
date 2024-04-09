param privateDnsZone string = 'demo.janne'

param location string

resource networkSecurityGroupAppGw 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: 'nsg-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-AppGw'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          description: 'Allow AppGw maintenance traffic'
        }
      }
    ]
  }
}

resource networkSecurityGroupVM 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: 'nsg-vm'
  location: location
  properties: {
    securityRules: []
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: 'vnet-appgw'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    subnets: [
      {
        name: 'snet-appgw'
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroupAppGw.id
          }
        }
      }
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroupVM.id
          }
        }
      }
    ]
  }
}

resource privateDNSZoneResource 'Microsoft.Network/privateDnsZones@2018-09-01' = {
  name: privateDnsZone
  location: 'global'
}

resource privateDNSZoneLinkToVNETResource 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: 'link'
  parent: privateDNSZoneResource
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource vmARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: 'vm'
  parent: privateDNSZoneResource
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: '10.0.1.4'
      }
    ]
  }
}

output subnets object[] = virtualNetwork.properties.subnets
