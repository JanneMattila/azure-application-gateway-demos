# Azure Application Gateway with Virtual Machine

## Scenario

TBD

## Setup

### Variables

```powershell
# Alternatively, you can use also public IP address FQDN of the AppGw:
$domain = "contoso00000000005.swedencentral.cloudapp.azure.com"

# Certificate password
$certificatePasswordPlainText = "<your certificate password>"
$certificatePassword = ConvertTo-SecureString -String $certificatePasswordPlainText -Force -AsPlainText

# VM password
$vmPasswordPlainText = "<your VM password>"
$vmPassword = ConvertTo-SecureString -String $vmPasswordPlainText -Force -AsPlainText
```

### Create certificate to enable SSL

Based on instructions from [here](https://docs.microsoft.com/en-us/azure/application-gateway/create-ssl-portal):

Using Windows PowerShell in 
```powershell
$cert = New-SelfSignedCertificate -certstorelocation cert:\localmachine\my -dnsname $domain

Export-PfxCertificate -Cert $cert -FilePath cert.pfx -Password $certificatePassword
```

### Deploy

```powershell
$result = .\deploy.ps1 -CertificatePassword $certificatePassword -VMPassword $vmPassword
$result
$result.outputs.appGateway
```

Query the logs to see if the authentication is not working:

```sql
AzureDiagnostics 
| where Category == "ApplicationGatewayFirewallLog" and TimeGenerated >= ago(5m) and 
        requestUri_s == "/app1/.auth/login/aad/callback" and action_s == "Blocked"
| distinct ruleId_s
```

### Test

```powershell
#
curl "http://$domain" --verbose

#
curl "https://$domain" --verbose --insecure
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-vm-demo" -Force
```
