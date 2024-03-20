param parentName string
param location string

resource parentGateway 'Microsoft.Network/applicationGateways@2020-06-01' existing = {
  name: parentName
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'log-appgw'
  location: location
}

resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag1'
  scope: parentGateway
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logAnalyticsDestinationType: 'Dedicated'
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

// From
// https://github.com/Azure/Azure-Network-Security/blob/master/Azure%20WAF/Workbook%20-%20WAF%20Monitor%20Workbook/WAFWorkbook_ARM.json
module wafWorkbook './WAFWorkbook_ARM.json' = {
  name: 'WAF-Workbook'
  params: {
    logAnalyticsWorkspace: logAnalyticsWorkspace.id
    workbookId: '904e82d0-4ccd-4b9f-bd3a-66c4f7bc3613' // Static workbook id
  }
}

// From
// https://github.com/Azure/Azure-Network-Security/tree/master/Azure%20WAF/Workbook%20-%20AppGw%20WAF%20Triage%20Workbook
module wafTriageWorkbook './WAFTriageWorkbook_ARM.json' = {
  name: 'WAF-Triage-Workbook'
  params: {
    workbookSourceId: logAnalyticsWorkspace.id
    workbookId: 'b65fbdd4-f042-4747-a843-b469cdbe1426' // Static workbook id
  }
}
