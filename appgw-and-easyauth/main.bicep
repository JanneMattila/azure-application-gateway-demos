param customDomain string
param appName string = 'contoso00000000001'
param adminAppName string = 'contoso00000000030'
param anonymousAppName string = 'contoso00000000031'
param location string = 'north europe'
param initialCreate bool

@secure()
param certificatePassword string

param clientId string
@secure()
param clientSecret string
param tenantId string = subscription().tenantId

param applicationGatewayName string = 'contoso0000000001'

var adminWebAppUri = '${adminAppName}.azurewebsites.net'
var anonymousWebAppUri = '${anonymousAppName}.azurewebsites.net'

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
        }
      }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: 'pip-appgw'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: appName
    }
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
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicIP.id
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
      {
        name: 'appGatewayFrontendPort-https'
        properties: {
          port: 443
        }
      }
    ]
    sslCertificates: [
      {
        name: 'cert'
        properties: {
          data: loadFileAsBase64('./cert.pfx')
          password: certificatePassword
        }
      }
    ]
    backendAddressPools: [
      {
        name: adminAppName
        properties: {
          backendAddresses: [
            {
              fqdn: adminWebAppUri
            }
          ]
        }
      }
      {
        name: anonymousAppName
        properties: {
          backendAddresses: [
            {
              fqdn: anonymousWebAppUri
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'probeAdminApp'
        properties: {
          protocol: 'Https'
          pickHostNameFromBackendHttpSettings: false
          host: adminWebAppUri
          path: '/healthz' // Only unauthenticated path
          interval: 30
          timeout: 30
          port: 443
          match: {
            statusCodes: [
              '200'
            ]
          }
        }
      }
      {
        name: 'probeAnonymousApp'
        properties: {
          protocol: 'Https'
          pickHostNameFromBackendHttpSettings: true
          path: '/'
          interval: 30
          timeout: 30
          port: 443
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
        name: 'rewriteRule1'
        properties: {
          rewriteRules: [
            // You can either use the default header 'X-ORIGINAL-HOST' and match that in the webapp config
            // or add this header 'X-Forwarded-Host':
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
            // Example of rewriting the path from "/admin/echo" to "/echo"
            // {
            //   ruleSequence: 200
            //   name: 'admin-path'
            //   conditions: [
            //     {
            //       variable: 'var_uri_path'
            //       pattern: '.*admin/(.*)'
            //       ignoreCase: true
            //     }
            //   ]
            //   actionSet: {
            //     urlConfiguration: {
            //       modifiedPath: '{var_uri_path_1}'
            //       reroute: false
            //     }
            //   }
            // }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettingsAdminApp'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'probeAdminApp')
          }
        }
      }
      {
        name: 'appGatewayBackendHttpSettingsAnonymousApp'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'probeAnonymousApp')
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
        }
      }
      {
        name: 'appGatewayHttpListener-https'
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
              'appGatewayFrontendPort-https'
            )
          }
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', applicationGatewayName, 'cert')
          }
          protocol: 'Https'
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
              anonymousAppName
            )
          }
          defaultBackendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'appGatewayBackendHttpSettingsAnonymousApp'
            )
          }
          defaultRewriteRuleSet: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/rewriteRuleSets',
              applicationGatewayName,
              'rewriteRule1'
            )
          }
          pathRules: [
            {
              name: '${adminAppName}path'
              properties: {
                paths: [
                  '/admin*'
                ]
                backendAddressPool: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendAddressPools',
                    applicationGatewayName,
                    adminAppName
                  )
                }
                backendHttpSettings: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                    applicationGatewayName,
                    'appGatewayBackendHttpSettingsAdminApp'
                  )
                }
                rewriteRuleSet: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/rewriteRuleSets',
                    applicationGatewayName,
                    'rewriteRule1'
                  )
                }
              }
            }
          ]
        }
      }
    ]
    redirectConfigurations: [
      {
        name: 'to-https'
        properties: {
          redirectType: 'Permanent'
          includePath: true
          includeQueryString: true
          targetListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-https'
            )
          }
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'https-rule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-http'
            )
          }
          redirectConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/redirectConfigurations',
              applicationGatewayName,
              'to-https'
            )
          }
        }
      }
      {
        name: 'backend-rule'
        properties: {
          priority: 200
          ruleType: 'PathBasedRouting'
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-https'
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

resource firewallPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: 'waf-policy'
  location: location
  properties: {
    customRules: [
      // Allow EasyAuth callback (you don't need to enable other rules below)
      // {
      //   priority: 10
      //   name: 'RuleAllowEasyAuth'
      //   action: 'Allow'
      //   ruleType: 'MatchRule'
      //   matchConditions: [
      //     {
      //       operator: 'EndsWith'
      //       negationConditon: false
      //       transforms: [
      //         'Lowercase'
      //       ]
      //       matchVariables: [
      //         {
      //           variableName: 'RequestUri'
      //         }
      //       ]
      //       matchValues: [
      //         '/admin/.auth/login/aad/callback'
      //       ]
      //     }
      //   ]
      // }
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
          ruleSetVersion: '1.0'
        }
      ]
      // https://learn.microsoft.com/en-us/azure/web-application-firewall/ag/application-gateway-waf-configuration
      exclusions: [
        {
          matchVariable: 'RequestArgKeys'
          selector: '/admin/.auth/login/aad/callback'
          selectorMatchOperator: 'EndsWith'
          exclusionManagedRuleSets: [
            {
              ruleSetType: 'Microsoft_DefaultRuleSet'
              ruleSetVersion: '2.1'

              ruleGroups: [
                {
                  ruleGroupName: 'PROTOCOL-ENFORCEMENT'
                  rules: [
                    {
                      ruleId: '920230'
                    }
                  ]
                }
                {
                  ruleGroupName: 'SQLI'
                  rules: [
                    {
                      ruleId: '942440'
                    }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  }
}

module monitoring './monitoring.bicep' = {
  name: 'monitoring'
  params: {
    parentName: applicationGateway.name
    location: location
  }
}

module webApps './webApps.bicep' = {
  name: 'webApp-deployments'
  params: {
    initialCreate: initialCreate
    appPlanName: 'appServicePlan1'
    adminAppName: adminAppName
    anonymousAppName: anonymousAppName
    image: 'DOCKER|jannemattila/echo:1.0.130'
    customPath: '/admin'
    proxyIp: publicIP.properties.ipAddress
    proxyHost: customDomain
    // Alternatively, you can use existing AppGW public IP FQDN: publicIP.properties.dnsSettings.fqdn
    // proxyHost: publicIP.properties.dnsSettings.fqdn
    location: location

    tenantId: tenantId
    clientId: clientId
    clientSecret: clientSecret
  }
}

output appGateway string = publicIP.properties.dnsSettings.fqdn
output ip string = publicIP.properties.ipAddress
