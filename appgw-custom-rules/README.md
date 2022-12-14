# Azure Application Gateway and custom rules


### Deploy

```powershell
.\deploy.ps1
```

### Test

```powershell
curl "http://$domain" --verbose
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-auth-demo" -Force
```
