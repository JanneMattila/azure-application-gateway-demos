param appServicePlanName string
param appServiceName string
param image string

param location string

resource parentAppServicePlan 'Microsoft.Web/serverfarms@2020-06-01' existing = {
  name: appServicePlanName
}

resource appService 'Microsoft.Web/sites@2020-06-01' = {
  name: appServiceName
  location: location
  kind: 'web'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    siteConfig: {
      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'

      linuxFxVersion: image
    }
    serverFarmId: parentAppServicePlan.id
    httpsOnly: false
    clientAffinityEnabled: false
  }
}

output address string = appService.properties.hostNames[0]
