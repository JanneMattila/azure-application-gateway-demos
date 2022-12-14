# Azure Application Gateway and custom rules

![Application gateway logs](https://user-images.githubusercontent.com/2357647/207596514-c6c7bea1-b68b-45fa-a6ca-0ecb3a2f7bbe.png)

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
