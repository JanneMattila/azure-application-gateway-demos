param parentName string
param location string

resource parentGateway 'Microsoft.Network/applicationGateways@2020-06-01' existing = {
  name: parentName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'log-appgw'
  location: location
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = {
  name: 'diag1'
  scope: parentGateway
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
    ]
  }
}
