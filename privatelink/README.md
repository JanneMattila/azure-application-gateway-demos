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
$resultProvider = .\provider\deploy.ps1 -CertificatePassword $certificatePassword
$resultProvider

# Resource Id
$resourceId = $resultProvider.Outputs.resourceId.value
# SubResource
$subResource = $resultProvider.Outputs.subResource.value

# Deployment of Fabrikam - Same tenant
$resultConsumer1 = .\consumer\deploy.ps1 -ResourceId $resourceId -SubResource $subResource -Customer "fabrikam"
$resultConsumer1

$uri1 = $resultConsumer1.Outputs.uri.value

# Deployment of Litware - Different tenant
Login-AzAccount
$resultConsumer2 = .\consumer\deploy.ps1 -ResourceId $resourceId -SubResource $subResource -Customer "litware"
$resultConsumer2

$uri2 = $resultConsumer2.Outputs.uri.value
```

### Test

```powershell
###
# Fabrikam->
curl "https://$uri1"

# Test connectivity to provider
curl --data "TCP 192.168.0.4 80" "https://$uri1/api/commands"
curl --data "TCP 192.168.0.4 443" "https://$uri1/api/commands"

curl --data 'HTTP GET "http://192.168.0.4/hello"' "https://$uri1/api/commands"
curl --data 'HTTP GET "https://192.168.0.4/hello"' "https://$uri1/api/commands"

curl --data 'HTTP GET "http://my.apps.jannemattila.com/hello"' "https://$uri1/api/commands"
curl --data 'HTTP GET "https://my.apps.jannemattila.com/hello"' "https://$uri1/api/commands"
# <-Fabrikam
###

###
# Litware->
curl "https://$uri1"

# Test connectivity to provider
curl --data "TCP 192.168.0.4 80" "https://$uri2/api/commands"
curl --data "TCP 192.168.0.4 443" "https://$uri2/api/commands"

curl --data 'HTTP GET "http://192.168.0.4/hello"' "https://$uri2/api/commands"
curl --data 'HTTP GET "https://192.168.0.4/hello"' "https://$uri2/api/commands"

curl --data 'HTTP GET "http://my.apps.jannemattila.com/hello"' "https://$uri2/api/commands"
curl --data 'HTTP GET "https://my.apps.jannemattila.com/hello"' "https://$uri2/api/commands"
# <-Litware
###
```

WAF will prevent using IP address:

![WAF](https://github.com/JanneMattila/azure-application-gateway-demos/assets/2357647/c9b5c6ad-5542-47d2-9cb0-2b8267462026)


Here is example console output:

```console
$ curl "https://$uri1"
Hello there!

$ curl --data "TCP 192.168.0.4 80" "https://$uri1/api/commands"
-> Start: TCP 192.168.0.4 80
OK
<- End: TCP 192.168.0.4 80 57.49ms

$ curl --data "TCP 192.168.0.4 443" "https://$uri1/api/commands"
-> Start: TCP 192.168.0.4 443
OK
<- End: TCP 192.168.0.4 443 7.93ms

$ curl --data 'HTTP GET "http://192.168.0.4/hello"' "https://$uri1/api/commands"
-> Start: HTTP GET "http://192.168.0.4/hello"
Forbidden Forbidden <html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>Microsoft-Azure-Application-Gateway/v2</center>
</body>
</html>

<- End: HTTP GET "http://192.168.0.4/hello" 27.26ms

$ curl --data 'HTTP GET "https://192.168.0.4/hello"' "https://$uri1/api/commands"
-> Start: HTTP GET "https://192.168.0.4/hello"
System.Net.Http.HttpRequestException: The SSL connection could not be established, see inner exception.
... <abbreviated>
<- End: HTTP GET "https://192.168.0.4/hello" 1156.80ms

$ curl --data 'HTTP GET "http://my.apps.jannemattila.com/hello"' "https://$uri1/api/commands"
-> Start: HTTP GET "http://my.apps.jannemattila.com/hello"
... <abbreviated>
X-ORIGINAL-HOST: my.apps.jannemattila.com
<- End: HTTP GET "http://my.apps.jannemattila.com/hello" 145.60ms

$ curl --data 'HTTP GET "https://my.apps.jannemattila.com/hello"' "https://$uri1/api/commands"
-> Start: HTTP GET "https://my.apps.jannemattila.com/hello"
System.Net.Http.HttpRequestException: The SSL connection could not be established, see inner exception.
... <abbreviated>
<- End: HTTP GET "https://my.apps.jannemattila.com/hello" 1329.35ms
```

If you get following error:

```console
The client has permission to perform action 
'Microsoft.Network/applicationGateways/PrivateEndpointConnectionsApproval/action' on scope
'/subscriptions/83f7bc39-edab-463f-b9e6-72ec6d7cf3a0/resourcegroups/rg-appgw-consumer-litware/providers/Microsoft.Network/privateEndpoints/pe-litware',
however the current tenant '6dd3249b-698d-410a-9014-ae5385d16aab'
is not authorized to access linked subscription '79d23b17-d065-4de5-ae2f-848fe5c55ff1'.
(Code:LinkedAuthorizationFailed)
```

Then check permissions and that you're using `manualPrivateLinkServiceConnections`
instead of `privateLinkServiceConnections` in your Bicep templates.

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-consumer-litware" -Force

Login-AzAccount
Remove-AzResourceGroup -Name "rg-appgw-consumer-fabrikam" -Force
Remove-AzResourceGroup -Name "rg-appgw-provider" -Force
```
