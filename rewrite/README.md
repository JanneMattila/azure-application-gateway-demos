# Rewrite

## Overview

This sample shows how to use rewrite rules in Application Gateway.

## Links

[Rewrite URL with Azure Application Gateway - Azure portal](https://learn.microsoft.com/en-us/azure/application-gateway/rewrite-url-portal)

[Rewrite HTTP headers and URL with Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/rewrite-http-headers-url)

## Setup

### Variables

```powershell
# Public fully qualified domain name of our AppGw
$domain = "contoso00000000002.northeurope.cloudapp.azure.com"
# Certificate password
$certificatePasswordPlainText = "<your certificate password>"
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
.\deploy.ps1 -CertificatePassword $certificatePassword
```

## Rewrite rule examples

### Accept-Language header

Example browser header for `Accept-Language`:

``` 
Accept-Language: en-US,en;q=0.9,fi;q=0.8,fr;q=0.7,mt;q=0.6
```

Rewrite rule:

```bicep
{
  ruleSequence: 200
  name: 'accept-language-to-querystring'
  conditions: [
    {
      variable: 'http_req_accept-language'
      ignoreCase: true
      negate: false
      pattern: '^([^,]*)'
    }
  ]
  actionSet: {
    urlConfiguration: {
      modifiedQueryString: 'lang={http_req_accept-language_1}'
    }
  }
}
```

Test regular expression:

```powershell
"en-US,en;q=0.9,fi;q=0.8,fr;q=0.7,mt;q=0.6" -match "^([^,]*)"
$matches[0]

"en-US" -match "^([^,]*)"
$matches[0]
```

Both should return `en-US`.

Test deployment:

```powershell
curl http://$domain --verbose
curl https://$domain --verbose --insecure

curl https://$domain/app1/hello --verbose --insecure
curl https://$domain/app1/hello -H "Accept-Language: fi-FI" --verbose --insecure
# Original request was: /hello?lang=fi-FI
curl https://$domain/app1/hello -H "Accept-Language: en-US" --verbose --insecure
# Original request was: /hello?lang=en-US
curl https://$domain/app1/hello -H "Accept-Language: en-US,en;q=0.9,fi;q=0.8,fr;q=0.7,mt;q=0.6" --verbose --insecure
# Original request was: /hello?lang=en-US
```
