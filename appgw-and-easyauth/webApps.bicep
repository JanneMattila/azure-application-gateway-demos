param appPlanName string
param skuName string = 'B1'
param appName1 string
param appName2 string
param image string

param tenantId string
param clientId string
@secure()
param clientSecret string

param customPath string
param proxyIp string
param proxyHost string
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

resource appService1 'Microsoft.Web/sites@2023-01-01' = {
  name: appName1
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
          headers: {
            // Azure Front Door header:
            // 'X-Forwarded-Host': [
            //   proxyHost
            // ]
          }
        }
      ]

      alwaysOn: true
      http20Enabled: true
      ftpsState: 'Disabled'

      linuxFxVersion: image

      appSettings: [
        {
          name: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          value: clientSecret
        }
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

resource certificate 'Microsoft.Web/certificates@2023-01-01' = {
  name: proxyHost
  location: location
  properties: {
    canonicalName: proxyHost
    serverFarmId: appServicePlan.id
  }
}

resource hostBinding 'Microsoft.Web/sites/hostNameBindings@2023-01-01' = {
  parent: appService1
  name: proxyHost
  properties: {
    hostNameType: 'Verified'
    sslState: 'Disabled'
    customHostNameDnsRecordType: 'CName'
    siteName: appService1.name
  }
}

resource authentication 'Microsoft.Web/sites/config@2023-01-01' = {
  name: 'authsettingsV2'
  parent: appService1
  properties: {
    httpSettings: {
      requireHttps: true
      // https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization#considerations-for-using-built-in-authentication
      forwardProxy: {
        // https://learn.microsoft.com/en-us/azure/application-gateway/how-application-gateway-works#modifications-to-the-request
        // convention: 'Standard' // X-Forwarded-Host
        convention: 'Custom'
        customHostHeaderName: 'X-ORIGINAL-HOST'
      }
      routes: {
        apiPrefix: '${customPath}/.auth'
      }
    }
    globalValidation: {
      redirectToProvider: 'azureactivedirectory'
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        login: {
          disableWWWAuthenticate: false
        }
        registration: {
          clientId: clientId
          clientSecretSettingName: 'MICROSOFT_PROVIDER_AUTHENTICATION_SECRET'
          openIdIssuer: 'https://sts.windows.net/${tenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${clientId}'
          ]
        }
      }
    }

    login: {
      tokenStore: {
        enabled: true
      }
      cookieExpiration: {
        convention: 'FixedTime'
        timeToExpiration: '08:00:00'
      }
      nonce: {
        validateNonce: true
        nonceExpirationInterval: '00:05:00'
      }
      preserveUrlFragmentsForLogins: true
      routes: {
        logoutEndpoint: '${customPath}/.auth/logout'
      }
    }
    platform: {
      enabled: true
      runtimeVersion: '~1'
    }
  }
}

module hostbindingEnable 'hostbinding.bicep' = {
  name: '${deployment().name}-enable-hostbinding'
  params: {
    appName: appService1.name
    proxyHost: proxyHost
    thumbprint: certificate.properties.thumbprint
  }
}

resource appService2 'Microsoft.Web/sites@2023-01-01' = {
  name: appName2
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
output name string = appService1.name
