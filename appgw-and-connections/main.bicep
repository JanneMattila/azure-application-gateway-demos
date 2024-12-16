param location string = resourceGroup().location
param username string
@secure()
param password string

param applicationGatewayName string

var vmAppName = 'app'

module network './network.bicep' = {
  name: 'vnet-deployment'
  params: {
    location: location
    username: username
    password: password
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
    ]
    sslCertificates: []
    trustedRootCertificates: []
    backendAddressPools: [
      {
        name: vmAppName
        properties: {
          backendAddresses: [
            {
              ipAddress: network.outputs.vm1PrivateIP
            }
            {
              ipAddress: network.outputs.vm2PrivateIP
            }
          ]
        }
      }
    ]
    probes: [
      {
        name: 'probeVMApp-http'
        properties: {
          protocol: 'Http'
          pickHostNameFromBackendHttpSettings: true
          path: '/Probe.aspx'
          interval: 5
          timeout: 5
          unhealthyThreshold: 1
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
          requestTimeout: 5
          cookieBasedAffinity: 'Enabled'
          connectionDraining: {
            enabled: true
            drainTimeoutInSec: 5
          }
          pickHostNameFromBackendAddress: true
          probeEnabled: true
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', applicationGatewayName, 'probeVMApp-http')
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
    ]
    urlPathMaps: []
    redirectConfigurations: []
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
          backendAddressPool: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendAddressPools',
              applicationGatewayName,
              vmAppName
            )
          }
          backendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              applicationGatewayName,
              'appGatewayBackendHttpSettingsVMApp-http'
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
          ruleSetVersion: '1.1'
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

output vm1PublicIP string = network.outputs.vm1PublicIP
output vm1PrivateIP string = network.outputs.vm1PrivateIP

output vm2PublicIP string = network.outputs.vm2PublicIP
output vm2PrivateIP string = network.outputs.vm2PrivateIP
