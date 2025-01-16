# Azure Application Gateway demos

Azure Application Gateway demos

```powershell
$appGw = Get-AzApplicationGateway -Name <name> -ResourceGroupName <resource-group-name>
Start-AzApplicationGateway -ApplicationGateway $appGw
```
