param appPlanName string
param skuName string = 'B1'
param appName string
param image string

param proxyIp string
param location string = resourceGroup().location

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
    siteConfig: {
      ipSecurityRestrictions: [
        {
          action: 'Allow'
          name: 'AppGateway'
          priority: 100
          ipAddress: '${proxyIp}/32'
          headers: {}
        }
      ]

      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'

      linuxFxVersion: image
      healthCheckPath: '/healthz'

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

output id string = appServicePlan.id
output name string = appService.name
