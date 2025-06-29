// Full address will be: 
// <applicationGatewayDomainName>.<location>.cloudapp.azure.com
// E.g., 
// contoso00000000002.northeurope.cloudapp.azure.com
param applicationGatewayDomainNamePrefix string

param location string = resourceGroup().location

var applicationGatewayName = 'agw-contoso'
var appServiceName = 'app-contoso-${uniqueString(resourceGroup().id, applicationGatewayDomainNamePrefix)}'
var applicationGatewayDomainName = '${applicationGatewayDomainNamePrefix}-${uniqueString(resourceGroup().id, applicationGatewayDomainNamePrefix)}'
var appServiceAppUri = '${appServiceName}.azurewebsites.net'

module network 'network.bicep' = {
  name: 'network'
  params: {
    location: location
    applicationGatewayDomainName: applicationGatewayDomainName
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    enableHttp2: true
    firewallPolicy: {
      id: firewallPolicy.id
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 125
    }
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: network.outputs.appGatewaySubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: network.outputs.publicIPId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort-http'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: appServiceName
        properties: {
          backendAddresses: [
            {
              fqdn: appServiceAppUri
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'probe'
        properties: {
          protocol: 'Http'
          pickHostNameFromBackendHttpSettings: true
          path: '/'
          interval: 30
          timeout: 30
          port: 80
          match: {
            statusCodes: [
              '200'
            ]
          }
        }
      }
    ]
    rewriteRuleSets: [
      {
        name: 'add-forwarded-host-header'
        properties: {
          rewriteRules: [
            {
              ruleSequence: 100
              name: 'add-forwarded-host-header'
              actionSet: {
                requestHeaderConfigurations: [
                  {
                    headerName: 'X-Forwarded-Host'
                    headerValue: '{var_host}'
                  }
                ]
              }
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'probe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener-http'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              applicationGatewayName,
              'appGatewayFrontendIP'
            )
          }
          frontendPort: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendPorts',
              applicationGatewayName,
              'appGatewayFrontendPort-http'
            )
          }
          protocol: 'Http'
          customErrorConfigurations: [
            {
              statusCode: 'HttpStatus403'
              customErrorPageUrl: 'https://raw.githubusercontent.com/JanneMattila/azure-application-gateway-demos/main/appgw-custom-rules/html/403.html'
            }
            {
              statusCode: 'HttpStatus502'
              customErrorPageUrl: 'https://raw.githubusercontent.com/JanneMattila/azure-application-gateway-demos/main/appgw-custom-rules/html/502.html'
            }
          ]
        }
      }
    ]
    urlPathMaps: [
      {
        name: 'paths'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              applicationGatewayName,
              appServiceName
            )
          }
          defaultBackendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'appGatewayBackendHttpSettings'
            )
          }
          defaultRewriteRuleSet: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/rewriteRuleSets',
              applicationGatewayName,
              'add-forwarded-host-header'
            )
          }
          pathRules: [
            {
              name: '${appServiceName}path'
              properties: {
                paths: [
                  '/*'
                ]
                backendAddressPool: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendAddressPools',
                    applicationGatewayName,
                    appServiceName
                  )
                }
                backendHttpSettings: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                    applicationGatewayName,
                    'appGatewayBackendHttpSettings'
                  )
                }
                rewriteRuleSet: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/rewriteRuleSets',
                    applicationGatewayName,
                    'add-forwarded-host-header'
                  )
                }
              }
            }
          ]
        }
      }
    ]
    redirectConfigurations: []
    requestRoutingRules: [
      {
        name: 'backend-rule'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 100
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-http'
            )
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', applicationGatewayName, 'paths')
          }
        }
      }
    ]
  }
}

resource firewallPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-07-01' = {
  name: 'waf-policy'
  location: location
  properties: {
    customRules: [
      // {
      //   priority: 10
      //   name: 'RuleAllowCorporateIPs'
      //   action: 'Allow'
      //   ruleType: 'MatchRule'
      //   matchConditions: [
      //     {
      //       operator: 'IPMatch'
      //       matchVariables: [
      //         {
      //           variableName: 'RemoteAddr'
      //         }
      //       ]
      //       matchValues: [
      //         '192.168.0.0/16'
      //       ]
      //     }
      //   ]
      // }
      {
        priority: 30
        name: 'RuleBlockIPs'
        action: 'Block'
        ruleType: 'MatchRule'
        matchConditions: [
          {
            operator: 'IPMatch'
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            matchValues: [
              '1.2.3.4'
              '2.3.4.5'
            ]
          }
        ]
      }
      {
        priority: 31
        name: 'RuleBlockCustomHeader'
        action: 'Block'
        ruleType: 'MatchRule'
        matchConditions: [
          {
            operator: 'Contains'
            negationConditon: false
            transforms: [
              'Lowercase'
            ]
            matchVariables: [
              {
                variableName: 'RequestHeaders'
                selector: 'x-custom-header'
              }
            ]
            matchValues: [
              'block-me'
            ]
          }
        ]
      }
      {
        priority: 50
        name: 'RuleGeoDeny'
        action: 'Log'
        ruleType: 'MatchRule'
        matchConditions: [
          {
            operator: 'GeoMatch'
            negationConditon: true
            transforms: []
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            matchValues: [
              'FI' // Finland
              'AX' // Åland Islands
              'SE' // Sweden
              'NO' // Norway
              'DK' // Denmark
              'EE' // Estonia
              'LV' // Latvia
              'LT' // Lithuania
            ]
          }
        ]
      }
      {
        priority: 90
        name: 'RuleRateLimit'
        action: 'Log'
        ruleType: 'RateLimitRule'
        rateLimitDuration: 'OneMin'
        rateLimitThreshold: 20
        state: 'Enabled'
        groupByUserSession: [
          {
            groupByVariables: [
              {
                variableName: 'ClientAddr'
              }
            ]
          }
        ]
        matchConditions: [
          {
            operator: 'IPMatch'
            negationConditon: true
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            matchValues: [
              '255.255.255.255/32'
            ]
          }
        ]
      }
      {
        name: 'FinlandRateLimit'
        priority: 91
        ruleType: 'RateLimitRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'GeoMatch'
            negationConditon: false
            matchValues: ['FI']
          }
        ]
        rateLimitThreshold: 4000
        rateLimitDuration: 'OneMin'
        groupByUserSession: [
          {
            groupByVariables: [
              {
                variableName: 'ClientAddr'
              }
            ]
          }
        ]
      }
      {
        name: 'NordicRateLimit'
        priority: 92
        ruleType: 'RateLimitRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'GeoMatch'
            negationConditon: false
            matchValues: ['SE', 'NO', 'DK', 'IS']
          }
        ]
        rateLimitThreshold: 2000
        rateLimitDuration: 'OneMin'
        groupByUserSession: [
          {
            groupByVariables: [
              {
                variableName: 'ClientAddr'
              }
            ]
          }
        ]        
      }
      {
        name: 'OtherCountriesRateLimit'
        priority: 93
        ruleType: 'RateLimitRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'GeoMatch'
            negationConditon: true
            matchValues: ['FI', 'SE', 'NO', 'DK', 'IS']
          }
        ]
        rateLimitThreshold: 1000
        rateLimitDuration: 'OneMin'
        groupByUserSession: [
          {
            groupByVariables: [
              {
                variableName: 'ClientAddr'
              }
            ]
          }
        ]        
      }
    ]
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
      exclusions: []
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = {
  name: 'asp-web'
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
  }
  properties: {
    reserved: true
  }
}

module appService './appService.bicep' = {
  name: 'appService-deployment'
  params: {
    appServicePlanName: appServicePlan.name
    appServiceName: appServiceName
    // If you want to use the echo image and experiment with the custom rules, uncomment the following lines:
    // image: 'DOCKER|jannemattila/echo:1.0.118'
    // port: '8080'
    // If you want to use the example blog image, uncomment the following lines:
    image: 'DOCKER|jannemattila/blog:2025-06-19'
    port: '80'
    customPath: '/'
    proxyIp: network.outputs.ipAddress
    proxyHost: network.outputs.fqdn
    location: location
  }
}

module networkTesterAppService './networkTesterAppService.bicep' = {
  name: 'network-tester-appService-deployment'
  params: {
    appServicePlanName: appServicePlan.name
    appServiceName: '${appServiceName}-tester'
    image: 'DOCKER|jannemattila/webapp-network-tester:1.0.69'
    location: location
  }
}

module monitoring './monitoring.bicep' = {
  name: 'monitoring'
  params: {
    parentName: applicationGateway.name
    location: location
  }
}

output appGwfqdn string = network.outputs.fqdn
output tester string = networkTesterAppService.outputs.address
