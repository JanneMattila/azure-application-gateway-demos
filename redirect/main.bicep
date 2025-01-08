// Full address will be: 
// <applicationGatewayDomainName>.<location>.cloudapp.azure.com
// E.g., 
// contoso00000000002.northeurope.cloudapp.azure.com
param appGwDomain string
param customDomain1 string
param customDomain2 string
param backendName string = 'backend'

param location string = resourceGroup().location

var applicationGatewayName = 'agw-contoso'
var backendUri = 'myip.jannemattila.com'

module network 'network.bicep' = {
  name: 'network'
  params: {
    location: location
    applicationGatewayDomainName: appGwDomain
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-04-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 2
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
        name: backendName
        properties: {
          backendAddresses: [
            {
              fqdn: backendUri
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'probe'
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
    rewriteRuleSets: []
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpsSettings'
        properties: {
          port: 443
          protocol: 'Https'
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
        name: 'appGatewayHttpListener-http-old'
        properties: {
          hostName: customDomain1
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
          customErrorConfigurations: []
        }
      }
      {
        name: 'appGatewayHttpListener-http-new'
        properties: {
          hostName: customDomain2
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
          customErrorConfigurations: []
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
              backendName
            )
          }
          defaultBackendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'appGatewayBackendHttpsSettings'
            )
          }
          pathRules: [
            {
              name: '${backendName}path'
              properties: {
                paths: [
                  '/*'
                ]
                backendAddressPool: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendAddressPools',
                    applicationGatewayName,
                    backendName
                  )
                }
                backendHttpSettings: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                    applicationGatewayName,
                    'appGatewayBackendHttpsSettings'
                  )
                }
              }
            }
          ]
        }
      }
      {
        name: 'paths-old'
        properties: {
          defaultRedirectConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/redirectConfigurations',
              applicationGatewayName,
              'old-to-new'
            )
          }
          pathRules: [
            {
              name: '${backendName}path'
              properties: {
                paths: [
                  '/*'
                ]
                redirectConfiguration: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/redirectConfigurations',
                    applicationGatewayName,
                    'old-to-new'
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
        name: 'old-to-new'
        properties: {
          redirectType: 'Permanent'
          includePath: true
          includeQueryString: true
          targetListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-http-new'
            )
          }
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'backend-rule-new'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 100
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-http-new'
            )
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', applicationGatewayName, 'paths')
          }
        }
      }
      {
        name: 'backend-rule-old'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 200
          redirectConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/redirectConfigurations',
              applicationGatewayName,
              'old-to-new'
            )
          }
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-http-old'
            )
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', applicationGatewayName, 'paths-old')
          }
        }
      }
    ]
  }
}
