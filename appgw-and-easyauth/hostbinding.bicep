param appName string
param proxyHost string
param thumbprint string

resource hostBinding 'Microsoft.Web/sites/hostNameBindings@2020-06-01' = {
  name: '${appName}/${proxyHost}'
  properties: {
    sslState: 'SniEnabled'
    thumbprint: thumbprint
  }
}
