# Azure Application Gateway with Easy Auth App Service

## Scenario

You want to use Azure Application Gateway in front of
Easy Auth enabled Azure App Service application.

Please read [preserve the original HTTP host name between a reverse proxy and its back-end web application](https://docs.microsoft.com/en-us/azure/architecture/best-practices/host-name-preservation)
as general guidance on this topic from Azure Architecture Center.

## Setup

### Variables

```powershell
# Public fully qualified custom domain name
$domain = "myapp.contoso.com"
# Alternatively, you can use also public IP address FQDN of the AppGw:
#$domain = "contoso00000000001.northeurope.cloudapp.azure.com"

# Certificate password
$certificatePasswordPlainText = "<your certificate password>"

# Create Azure AD app used in authentication
$appPathIfNeeded = "/app1" # In this demo "app1" is the "secured" application
$json = @"
{
  "displayName": "$domain",
  "signInAudience": "AzureADMyOrg",
  "requiredResourceAccess": [
    {
      "resourceAppId": "00000003-0000-0000-c000-000000000000",
      "resourceAccess": [
        {
          "id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
          "type": "Scope"
        }
      ]
    },
  ],
  "web": {
    "implicitGrantSettings": {
      "enableIdTokenIssuance": true
    },
    "redirectUris": [
      "https://$domain$appPathIfNeeded/.auth/login/aad/callback"
    ]
  }
}
"@

$json

$applicationResponse = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications" -Method POST -Payload $json
$application = $applicationResponse.Content | ConvertFrom-Json
$application.appId

$secretResponse = Invoke-AzRestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$($application.id)/addPassword" -Method POST
$secret = $secretResponse.Content | ConvertFrom-Json

$clientId = $application.appId
$clientSecretPlainText = $secret.secretText

$clientSecret = ConvertTo-SecureString -String $clientSecretPlainText -Force -AsPlainText
```

### Create certificate to enable SSL

Based on instructions from [here](https://docs.microsoft.com/en-us/azure/application-gateway/create-ssl-portal):

```powershell
$cert = New-SelfSignedCertificate -certstorelocation cert:\localmachine\my -dnsname $domain

$certificatePassword = ConvertTo-SecureString -String $certificatePasswordPlainText -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath cert.pfx -Password $certificatePassword
```

### Handle custom domain name

```powershell	
# Get custom domain verification id
$params = @{
  ResourceProviderName = "Microsoft.App"
  ResourceType = "getCustomDomainVerificationId"
  ApiVersion = "2023-08-01-preview"
  Method = "POST"
}
$customDomainVerificationId = (Invoke-AzRestMethod @params).Content | ConvertFrom-Json
# Note: This is **per** subscription!
$customDomainVerificationId

# Create TXT record in your DNS zone -> $customDomainVerificationId
# Create CNAME record in your DNS zone -> $domain -> <yourappservice>.azurewebsites.net
# After deployment, create A record in your DNS zone -> $domain -> <public IP of AppGw>
```

### Deploy

```powershell
.\deploy.ps1 `
  -CertificatePassword $certificatePassword `
  -ClientId $clientId `
  -ClientSecret $clientSecret `
  -CustomDomain $domain
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
