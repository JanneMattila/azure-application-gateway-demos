# Azure Application Gateway and connections

## Scenario

[Cookie-based affinity](https://learn.microsoft.com/en-us/azure/application-gateway/configuration-http-settings#cookie-based-affinity)

[Connection draining](https://learn.microsoft.com/en-us/azure/application-gateway/configuration-http-settings#connection-draining)

[Getting Started with AppCmd.exe](https://learn.microsoft.com/en-us/iis/get-started/getting-started-with-iis/getting-started-with-appcmdexe)

[Troubleshoot Azure Application Gateway session affinity issues](https://learn.microsoft.com/en-us/azure/application-gateway/how-to-troubleshoot-application-gateway-session-affinity-issues)

[503 Service Unavailable](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503)

[Administrative State (Admin State) in Azure Load Balancer](https://learn.microsoft.com/en-us/azure/load-balancer/admin-state-overview)

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
$result.outputs.appGwFQDN.value
```

```powershell
# Connect to the VM
$vmPasswordPlainText | clip
mstsc /v:$($result.outputs.vm1PublicIP.value) /f
mstsc /v:$($result.outputs.vm2PublicIP.value) /f
```

### Test

```powershell
start "http://$domain"
start "http://$($result.outputs.vm1.value)"
start "http://$($result.outputs.vm2FQDN.value)"

#
curl "http://$domain" --verbose

# Restart entire IIS
iisreset

# Site restart
. $env:systemroot\system32\inetsrv\AppCmd.exe stop site "Default Web Site"
. $env:systemroot\system32\inetsrv\AppCmd.exe start site "Default Web Site"

# Apppool - overlapped restart
. $env:systemroot\system32\inetsrv\AppCmd.exe recycle apppool "DefaultAppPool"

# Update backend pool
$appGw = Get-AzApplicationGateway -Name "contoso0000000025" -ResourceGroupName "rg-appgw-connections"
$backendPool = $appGw.BackendAddressPools | Where-Object { $_.Name -eq "app" }

$backendIPs = @("10.0.1.4", "10.0.1.5") # Both VMs
$backendIPs = @("10.0.1.4") # Only one VM
$backendIPs = @("10.0.1.5") # Only one VM

$appGw = Set-AzApplicationGatewayBackendAddressPool `
 -ApplicationGateway $appGw `
 -Name $backendPool.Name `
 -BackendIPAddresses $backendIPs

Set-AzApplicationGateway -ApplicationGateway $appGw

# Force the VM to be unhealthy


```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-connections" -Force
```
