# Azure Application Gateway and Private link

## Scenario

You have company `Contoso` providing web application to it's customer
`Fabricam`.

[Application Gateway Private Link](https://learn.microsoft.com/en-us/azure/application-gateway/private-link)

[Configure Azure Application Gateway Private Link](https://learn.microsoft.com/en-us/azure/application-gateway/private-link-configure)

## Setup

### Variables

```powershell

# Certificate password
$domain = "*.apps.jannemattila.com"
$domain1 = "customer1.apps.jannemattila.com"
$certificatePasswordPlainText = "<your certificate password>"
$certificatePassword = ConvertTo-SecureString -String $certificatePasswordPlainText -Force -AsPlainText
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
$resultContoso = .\contoso\deploy.ps1 -CertificatePassword $certificatePassword
$resultContoso

# Resource Id
$resourceId = $resultContoso.Outputs.resourceId.value
# SubResource
$subResource = $resultContoso.Outputs.subResource.value

$resultFabrikam = .\fabrikam\deploy.ps1 -ResourceId $resourceId -SubResource $subResource -PrivateEndpointName "pe-fabrikam"
$resultFabrikam

$fabrikamUri = $resultFabrikam.Outputs.uri.value
```

### Test

```powershell
curl "https://$fabrikamUri"

# Test connectivity
curl --data "TCP 192.168.0.4 80" "https://$fabrikamUri/api/commands"
curl --data "TCP 192.168.0.4 443" "https://$fabrikamUri/api/commands"

curl --data 'HTTP GET "http://192.168.0.4/hello"' "https://$fabrikamUri/api/commands"
curl --data 'HTTP GET "https://192.168.0.4/hello"' "https://$fabrikamUri/api/commands"
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-provider" -Force
Remove-AzResourceGroup -Name "rg-appgw-consumer1" -Force
```
