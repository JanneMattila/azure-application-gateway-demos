# Azure Application Gateway and connections

## Scenario

https://learn.microsoft.com/en-us/azure/application-gateway/configuration-http-settings#connection-draining

## Setup

### Variables

```powershell
# FQDN of the AppGw:
$domain = "contoso0000000025.swedencentral.cloudapp.azure.com"

# VM password
$vmPasswordPlainText = "<your VM password>"
$vmPassword = ConvertTo-SecureString -String $vmPasswordPlainText -Force -AsPlainText
```

### Deploy

```powershell
$result = .\deploy.ps1 -ApplicationGatewayName "contoso0000000025" -VMPassword $vmPassword
$result
$result.outputs.appGwFQDN
```

```powershell
# Connect to the VM
$vmPasswordPlainText | clip
mstsc /v:$($result.outputs.vm1FQDN.value) /f
mstsc /v:$($result.outputs.vm2FQDN.value) /f
```

### Test

```powershell
start "http://$domain"
start "http://$($result.outputs.vm1FQDN.value)"
start "http://$($result.outputs.vm2FQDN.value)"

#
curl "http://$domain" --verbose
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-connections" -Force
```
