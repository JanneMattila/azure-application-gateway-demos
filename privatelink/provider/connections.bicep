param applicationGatewayName string

resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' existing = {
  name: applicationGatewayName
}

resource pecFabrikam 'Microsoft.Network/applicationGateways/privateEndpointConnections@2023-09-01' = {
  name: 'pe-fabrikam.2123c155-e420-40c6-8e8e-e1454cbc90c7'
  parent: applicationGateway
  properties: {
    privateLinkServiceConnectionState: {
      actionsRequired: 'None'
      description: 'Fabrikam request approved 13th of February 2024'
      status: 'Approved'
    }
  }
}

resource pecLitware 'Microsoft.Network/applicationGateways/privateEndpointConnections@2023-09-01' = {
  name: 'pe-litware.d7b49a71-8e7b-43ba-92fe-311f2f571272'
  parent: applicationGateway
  properties: {
    privateLinkServiceConnectionState: {
      actionsRequired: 'None'
      description: 'Litware request approved 13th of February 2024'
      status: 'Approved'
    }
  }
}
