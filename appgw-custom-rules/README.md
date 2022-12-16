# Azure Application Gateway and custom rules

### Deploy

```powershell
.\deploy.ps1
```

### Test

```powershell
curl "http://$domain" --verbose
```

### Analyze logs

![Application gateway logs](https://user-images.githubusercontent.com/2357647/207596514-c6c7bea1-b68b-45fa-a6ca-0ecb3a2f7bbe.png)

Get usage in last 60 minutes grouped by Client IP:

```sql
AzureDiagnostics
| where Category == 'ApplicationGatewayAccessLog' and 
        OperationName == 'ApplicationGatewayAccess' and
        TimeGenerated >= ago(60min)
| summarize count() by clientIP_s
| project IP=clientIP_s, Requests=count_
| where Requests > 50
| order by Requests
```

| IP      | Requests |
| ------- | -------- |
| 1.2.3.4 | 100      |
| 2.3.4.5 | 88       |

You can use [rule-updater.ps1](./rule-updater.ps1) to create custom rule for blocking high usage:

```powershell
# Block all IPs that have made over 1000 requests in last 60 minutes
.\rule-updater.ps1 -RequestLimit 1000 -Minutes 60
```

You can use [rule-geo.ps1](./rule-geo.ps1) to update your Geo Matching rule action:

```powershell
# Update Geo Matching rule to use Action 'Log'
.\rule-geo.ps1 -Action Log

# Update Geo Matching rule to use Action 'Block'
.\rule-geo.ps1 -Action Block
```

#### Test `RuleBlockIPs`

```bicep
// ...
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
]
// ...
```

#### Test `RuleBlockCustomHeader`

```bicep
// ...
customRules: [
  {
    priority: 100
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
]
// ...
```

Test header filtering:

```powershell
curl -H "x-custom-header: aablock-me"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
curl -H "x-custom-header: aablock-meaa"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
curl -H "x-custom-header: good"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
```

Use tester app to connect to our App Gateway to test Geo filtering:

```powershell
curl --data "HTTP GET http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo"  http://contoso00000000020-tester.azurewebsites.net/api/commands
```

If you're blocked, you should get this error message if haven't created custom error pages:

```html
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
```

This example contains following custom error pages [403](./html/403.html) and [502](./html/502.html).

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-custom-rules-demo" -Force
```
