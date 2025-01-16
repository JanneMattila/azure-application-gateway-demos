param location string

resource networkSecurityGroupAppGw 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: 'nsg-appgw'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          description: 'Allow  HTTP traffic'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 110
          description: 'Allow HTTPS traffic'
        }
      }
      {
        name: 'Allow-AppGw'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          direction: 'Inbound'
          priority: 200
          description: 'Allow AppGw maintenance traffic'
        }
      }
    ]
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
    ]
  }
}

output subnets object[] = virtualNetwork.properties.subnets
