// Full address will be: 
// <applicationGatewayDomainName>.<location>.cloudapp.azure.com
// E.g., 
// contoso00000000002.northeurope.cloudapp.azure.com
param applicationGatewayDomainName string
param appServiceName string

param location string = resourceGroup().location

var applicationGatewayName = 'agw-contoso'
var appServiceAppUri = '${appServiceName}.azurewebsites.net'

module network 'network.bicep' = {
  name: 'network'
  params: {
    location: location
    applicationGatewayDomainName: applicationGatewayDomainName
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2020-06-01' = {
  name: applicationGatewayName
  location: location
  properties: {
    enableHttp2: true
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
    }
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
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
          firewallPolicy: {
            id: firewallPolicy.id
          }
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'appGatewayFrontendPort-http')
          }
          protocol: 'Http'
        }
      }
    ]
    urlPathMaps: [
      {
        name: 'paths'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, appServiceName)
          }
          defaultBackendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'appGatewayBackendHttpSettings')
          }
          defaultRewriteRuleSet: {
            id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', applicationGatewayName, 'add-forwarded-host-header')
          }
          pathRules: [
            {
              name: '${appServiceName}path'
              properties: {
                paths: [
                  '/*'
                ]
                backendAddressPool: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, appServiceName)
                }
                backendHttpSettings: {
                  id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'appGatewayBackendHttpSettings')
                }
                rewriteRuleSet: {
                  id: resourceId('Microsoft.Network/applicationGateways/rewriteRuleSets', applicationGatewayName, 'add-forwarded-host-header')
                }
              }
            }
          ]
        }
      }
    ]
    redirectConfigurations: [
    ]
    requestRoutingRules: [
      {
        name: 'backend-rule'
        properties: {
          ruleType: 'PathBasedRouting'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'appGatewayHttpListener-http')
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', applicationGatewayName, 'paths')
          }
        }
      }
    ]
  }
}

resource firewallPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2021-03-01' = {
  name: 'waf-policy'
  location: location
  properties: {
    customRules: [
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
        name: 'RuleBlockMe'
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
        priority: 40
        name: 'RuleGeoAllow'
        action: 'Allow'
        ruleType: 'MatchRule'
        matchConditions: [
          {
            operator: 'GeoMatch'
            negationConditon: false
            transforms: [
            ]
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            matchValues: [
              'FI' // Finland
              'AX' // Åland Islands
            ]
          }
        ]
      }
      {
        priority: 60
        name: 'RuleGeoDeny'
        action: 'Block'
        ruleType: 'MatchRule'
        matchConditions: [
          {
            operator: 'GeoMatch'
            negationConditon: true
            transforms: [
            ]
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            matchValues: [
              'AF'
              'AL'
              'DZ'
              'AD'
              'AS'
              'AO'
              'AI'
              'AQ'
              'AM'
              'AW'
              'AG'
              'AR'
              'AU'
              'AT'
              'AZ'
              'BS'
              'BH'
              'BD'
              'BB'
              'BY'
              'BE'
              'BZ'
              'BJ'
              'BM'
              'BT'
              'BO'
              'BQ'
              'BA'
              'BW'
              'BV'
              'BR'
              'IO'
              'VG'
              'BN'
              'BG'
              'BF'
              'BI'
              'CV'
              'KH'
              'CM'
              'CA'
              'KY'
              'CF'
              'TD'
              'CL'
              'CN'
              'CX'
              'CC'
              'CO'
              'KM'
              'CG'
              'CD'
              'CK'
              'CR'
              'HR'
              'CU'
              'CW'
              'CY'
              'CZ'
              'CI'
              'DK'
              'DJ'
              'DM'
              'DO'
              'EC'
              'EG'
              'SV'
              'GQ'
              'EE'
              'ER'
              'SZ'
              'ET'
              'FK'
              'FO'
              'FJ'
              'FI'
              'FR'
              'GF'
              'PF'
              'TF'
              'GA'
              'GM'
              'GE'
              'DE'
              'GH'
              'GI'
              'GR'
              'GL'
              'GD'
              'GP'
              'GU'
              'GT'
              'GG'
              'GN'
              'GW'
              'GY'
              'HT'
              'HM'
              'HN'
              'HK'
              'HU'
              'IS'
              'IN'
              'ID'
              'IR'
              'IQ'
              'IE'
              'IM'
              'IL'
              'IT'
              'JM'
              'JP'
              'JE'
              'KZ'
              'JO'
              'KE'
              'KI'
              'KR'
              'KW'
              'KG'
              'LA'
              'LV'
              'LB'
              'LS'
              'LR'
              'LY'
              'LI'
              'LT'
              'LU'
              'MO'
              'MY'
              'MG'
              'MW'
              'MV'
              'ML'
              'MT'
              'MH'
              'MQ'
              'MR'
              'MU'
              'FM'
              'YT'
              'MX'
              'MD'
              'MC'
              'MN'
              'ME'
              'MS'
              'MA'
              'MZ'
              'MM'
              'NA'
              'NR'
              'NP'
              'NL'
              'NC'
              'NZ'
              'NI'
              'NE'
              'NG'
              'NU'
              'NF'
              'KP'
              'MK'
              'MP'
              'NO'
              'OM'
              'PK'
              'PW'
              'PS'
              'PA'
              'PG'
              'PY'
              'PE'
              'PH'
              'PN'
              'PL'
              'PT'
              'PR'
              'QA'
              'RO'
              'RU'
              'RW'
              'RE'
              'BL'
              'KN'
              'LC'
              'MF'
              'PM'
              'VC'
              'WS'
              'SM'
              'SA'
              'SN'
              'RS'
              'SC'
              'SL'
              'SG'
              'SX'
              'SK'
              'SI'
              'SB'
              'SO'
              'ZA'
              'GS'
              'SS'
              'ES'
              'LK'
              'SH'
              'SD'
              'SR'
              'SJ'
              'SE'
              'CH'
              'SY'
              'ST'
              'TW'
              'TJ'
              'TZ'
              'TL'
              'TH'
              'TG'
              'TK'
              'TO'
              'TT'
              'TN'
              'TR'
              'TM'
              'TC'
              'TV'
              'UM'
              'VI'
              'UG'
              'UA'
              'AE'
              'GB'
              'US'
              'UY'
              'UZ'
              'VU'
              'VA'
              'VE'
              'VN'
              'WF'
              'YE'
              'ZM'
              'ZW'
              'AX'
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
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
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

module echoAppService './echoAppService.bicep' = {
  name: 'echo-appService'
  params: {
    appServicePlanName: appServicePlan.name
    appServiceName: appServiceName
    image: 'DOCKER|jannemattila/echo:1.0.96'
    customPath: '/'
    proxyIp: network.outputs.ipAddress
    location: location
  }
}

module networkTesterAppService './networkTesterAppService.bicep' = {
  name: 'network-tester-appService'
  params: {
    appServicePlanName: appServicePlan.name
    appServiceName: '${appServiceName}-tester'
    image: 'DOCKER|jannemattila/webapp-network-tester:1.0.53'
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
