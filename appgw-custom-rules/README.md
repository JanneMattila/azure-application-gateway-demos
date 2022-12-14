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

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-auth-demo" -Force
```
