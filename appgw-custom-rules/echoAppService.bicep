param appServicePlanName string
param appServiceName string
param image string

param customPath string
param proxyIp string
param proxyHost string
param location string

resource parentAppServicePlan 'Microsoft.Web/serverfarms@2020-06-01' existing = {
  name: appServicePlanName
}

resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: appServiceName
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
        }
      ]

      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'

      linuxFxVersion: image

      appSettings: [
        {
          name: 'CUSTOM_PATH'
          value: customPath
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'CUSTOM_ALLOW_ALL_PROXIES'
          value: 'true'
        }
        {
          name: 'CUSTOM_ALLOWED_HOST'
          value: proxyHost
        }
      ]
    }
    serverFarmId: parentAppServicePlan.id
    httpsOnly: false
    clientAffinityEnabled: false
  }
}

output name string = appService.name
