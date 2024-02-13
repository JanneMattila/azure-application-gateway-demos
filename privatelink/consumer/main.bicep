param customer string
param privateLinkResourceId string
param subResource string
param privateEndpointName string
param appPlanName string = 'appPlan'
param skuName string = 'B1'
param appName string = uniqueString(resourceGroup().id)
param image string = 'DOCKER|jannemattila/webapp-network-tester:1.0.66'
param location string = resourceGroup().location

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: 'vnet-appgw'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '192.168.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'snet-privatelink'
        properties: {
          addressPrefix: '192.168.0.0/24'
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '192.168.1.0/24'
          delegations: [
            {
              name: 'appservicedelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
        }
      }
    ]
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: virtualNetwork.properties.subnets[0].id
    }
    customNetworkInterfaceName: 'nic-${privateEndpointName}'
    // This requires approval from provider side
    manualPrivateLinkServiceConnections: [
      {
        name: 'privateLinkServiceConnection'
        properties: {
          privateLinkServiceId: privateLinkResourceId
          groupIds: [
            subResource
          ]
          requestMessage: 'Request coming from ${customer}'
        }
      }
    ]
    // This does not require approval but has to be done inside same tenant
    // privateLinkServiceConnections: [
    // ...      
    // ]
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: appPlanName
  location: location
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'web'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    virtualNetworkSubnetId: virtualNetwork.properties.subnets[1].id

    siteConfig: {
      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'

      linuxFxVersion: image

      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
      ]
    }
    serverFarmId: appServicePlan.id
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

output uri string = appService.properties.defaultHostName
