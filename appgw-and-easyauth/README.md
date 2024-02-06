# Azure Application Gateway with Easy Auth App Service

## Scenario

You want to use Azure Application Gateway in front of
Easy Auth enabled Azure App Service application.

Please read [preserve the original HTTP host name between a reverse proxy and its back-end web application](https://docs.microsoft.com/en-us/azure/architecture/best-practices/host-name-preservation)
as general guidance on this topic from Azure Architecture Center.

## Setup

### Variables

```powershell
# Public fully qualified domain name of our AppGw
$domain = "contoso00000000001.northeurope.cloudapp.azure.com"
# Certificate password
$certificatePasswordPlainText = "<your certificate password>"

# Azure AD app used in authentication
$clientId = "<your client id>"
$clientSecretPlainText = "<your client secret>"
```

### Create certificate to enable SSL

Based on instructions from [here](https://docs.microsoft.com/en-us/azure/application-gateway/create-ssl-portal):

```powershell
$cert = New-SelfSignedCertificate -certstorelocation cert:\localmachine\my -dnsname $domain

$certificatePassword = ConvertTo-SecureString -String $certificatePasswordPlainText -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath cert.pfx -Password $certificatePassword
```

### Deploy

```powershell
$clientSecret = ConvertTo-SecureString -String $clientSecretPlainText -Force -AsPlainText

# If you use default tenant
.\deploy.ps1 -CertificatePassword $certificatePassword -ClientId $clientId -ClientSecret $clientSecret
```

### Test

```powershell
# Will redirect to HTTPS
curl "http://$domain" --verbose
curl "http://$domain/app1/" --verbose

# Will return anonymous page content
curl "https://$domain" --verbose --insecure
curl "https://$domain/any/path/here" --verbose --insecure

# Forces authentication
curl "https://$domain/app1" --verbose --insecure
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-easyauth-demo" -Force
```
