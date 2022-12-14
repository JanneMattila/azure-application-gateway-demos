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

```sql
AzureDiagnostics
| where  Category == 'ApplicationGatewayFirewallLog'
| summarize count() by clientIp_s
| project ip=clientIp_s, requests=count_
| where requests > 3
| order by requests
```

| ip      | requests |
| ------- | -------- |
| 1.2.3.4 | 100      |
| 2.3.4.5 | 88       |

#### Test `RuleBlockMe`

```powershell
curl -H "x-custom-header: aablock-me"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
curl -H "x-custom-header: aablock-meaa"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
curl -H "x-custom-header: good"  http://contoso00000000002.northeurope.cloudapp.azure.com/pages/echo
```

```html
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-auth-demo" -Force
```
