param location string = 'swedencentral'
@secure()
param appGwCertificatePassword string
param applicationGatewayName string = 'contoso0000000035'

param appName string = 'app1'
param appFqdn string

module network './network.bicep' = {
  name: 'vnet-deployment'
  params: {
    location: location
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
      domainNameLabel: applicationGatewayName
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
      maxCapacity: 2
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
            id: network.outputs.subnets[0].id
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
          data: loadFileAsBase64('./AppGw.pfx')
          password: appGwCertificatePassword
        }
      }
    ]
    trustedRootCertificates: [
      {
        name: 'JanneCorpRootCA'
        properties: {
          data: loadFileAsBase64('./JanneCorpRootCA.cer')
        }
      }
    ]
    // authenticationCertificates: [
    //   {
    //     name: 'JanneCorpRootCA'
    //     properties: {
    //       data: loadFileAsBase64('./JanneCorpRootCA.cer')
    //     }
    //   }
    // ]
    backendAddressPools: [
      {
        name: appName
        properties: {
          backendAddresses: [
            {
              fqdn: appFqdn
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'probe-https'
        properties: {
          protocol: 'Https'
          pickHostNameFromBackendHttpSettings: true
          path: '/'
          interval: 30
          timeout: 30
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
          rewriteRules: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettingsVMApp-http'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probeEnabled: false
        }
      }
      {
        name: 'appGatewayBackendHttpSettingsVMApp-https'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'probe-https')
          }
        }
      }
    ]
    trustedClientCertificates: [
      {
        name: 'JanneCorpRootCA'
        properties: {
          data: loadFileAsBase64('./JanneCorpRootCA.cer')
        }
      }
    ]
    sslProfiles: [
      {
        name: 'appGatewaySslProfile-https'
        properties: {
          trustedClientCertificates: [
            {
              id: resourceId(
                'Microsoft.Network/applicationGateways/trustedClientCertificates',
                applicationGatewayName,
                'JanneCorpRootCA'
              )
            }
          ]
          clientAuthConfiguration: {
            verifyClientCertIssuerDN: true
            verifyClientRevocation: 'None'
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
          sslProfile: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/sslProfiles',
              applicationGatewayName,
              'appGatewaySslProfile-https'
            )
          }
        }
      }
    ]
    urlPathMaps: []
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
        name: 'http-rule'
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
        name: 'https-rule'
        properties: {
          priority: 200
          ruleType: 'Basic'
          httpListener: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/httpListeners',
              applicationGatewayName,
              'appGatewayHttpListener-https'
            )
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, appName)
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'appGatewayBackendHttpSettingsVMApp-https'
            )
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
    customRules: []
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
      exclusions: []
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

output appGwPublicIP string = publicIP.properties.ipAddress
output appGwFQDN string = publicIP.properties.dnsSettings.fqdn
