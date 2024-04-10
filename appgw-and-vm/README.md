# Azure Application Gateway with Virtual Machine

## Scenario

TBD

https://learn.microsoft.com/en-us/azure/application-gateway/self-signed-certificates

https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-backend-health-troubleshooting#trusted-root-certificate-mismatch-root-certificate-is-available-on-the-backend-server

## Setup

### Variables

```powershell
# Alternatively, you can use also public IP address FQDN of the AppGw:
$domain = "contoso0000000005.swedencentral.cloudapp.azure.com"

# Certificate password
$certificatePasswordPlainText = "<your certificate password>"
$certificatePassword = ConvertTo-SecureString -String $certificatePasswordPlainText -Force -AsPlainText

# VM password
$vmPasswordPlainText = "<your VM password>"
$vmPassword = ConvertTo-SecureString -String $vmPasswordPlainText -Force -AsPlainText
```


## Create certificate setup

Here is example if you want to create certificate chain (based on [this](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/certauth)):

```powershell
# Create Root CA
$rootCA = New-SelfSignedCertificate `
  -Subject "JanneCorp Root CA" `
  -FriendlyName "JanneCorp Root CA" `
  -CertStoreLocation "cert:\LocalMachine\My" `
  -NotAfter (Get-Date).AddYears(20) `
  -KeyUsageProperty All -KeyUsage CertSign, CRLSign, DigitalSignature

$rootPassword = ConvertTo-SecureString -String "1234" -Force -AsPlainText

Get-ChildItem -Path cert:\localMachine\my\$($rootCA.Thumbprint) | 
  Export-PfxCertificate -FilePath JanneCorpRootCA.pfx -Password $rootPassword

Export-Certificate -Cert cert:\localMachine\my\$($rootCA.Thumbprint) -FilePath JanneCorpRootCA.cer

# Create Intermediate Certificate
$intermediateCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\localmachine\my `
  -Subject "JanneCorp Intermediate certificate" `
  -FriendlyName "JanneCorp Intermediate certificate" `
  -Signer $rootCA `
  -NotAfter (Get-Date).AddYears(20) `
  -KeyUsageProperty All -KeyUsage CertSign, CRLSign, DigitalSignature `
  -TextExtension @("2.5.29.19={text}CA=1&pathlength=1")

$intermediatePassword = ConvertTo-SecureString -String "2345" -Force -AsPlainText

Get-ChildItem -Path cert:\localMachine\my\$($intermediateCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath IntermediateCertificate.pfx -Password $intermediatePassword

Export-Certificate -Cert cert:\localMachine\my\$($intermediateCertificate.Thumbprint) -FilePath IntermediateCertificate.cer

# Create AppGw Certificate
$appGwCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\localmachine\my `
  -DnsName $domain `
  -FriendlyName $domain `
  -Signer $intermediateCertificate `
  -NotAfter (Get-Date).AddYears(20)

$appGwPassword = ConvertTo-SecureString -String "3456" -Force -AsPlainText

Get-ChildItem -Path cert:\localMachine\my\$($appGwCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath AppGw.pfx -Password $appGwPassword

# Create VM Certificate
$vmCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\localmachine\my `
  -DnsName "vm.demo.janne" `
  -FriendlyName "vm.demo.janne" `
  -Signer $intermediateCertificate `
  -NotAfter (Get-Date).AddYears(20)

$vmCertificatePassword = ConvertTo-SecureString -String "4567" -Force -AsPlainText

Get-ChildItem -Path cert:\localMachine\my\$($vmCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath vm.pfx -Password $vmCertificatePassword
```

### Convert pfx to PEM

[Converting pfx to pem using openssl](https://stackoverflow.com/questions/15413646/converting-pfx-to-pem-using-openssl)

```bash
certificatePasswordPlainText="4567"

openssl pkcs12 -in vm.pfx -out vm_key.pem -nocerts -nodes -passin pass:$certificatePasswordPlainText
openssl pkcs12 -in vm.pfx -clcerts -nokeys -out vm_cert1.pem -nodes -passin pass:$certificatePasswordPlainText
openssl pkcs12 -in vm.pfx -cacerts -nokeys -out vm_cert2.pem -nodes -passin pass:$certificatePasswordPlainText
cat vm_cert1.pem vm_cert2.pem > vm_cert.pem
```

### Deploy

```powershell
$result = .\deploy.ps1 -CertificatePassword $appGwPassword -VMPassword $vmPassword
$result
$result.outputs.appGwFQDN
```

```powershell
# Connect to the VM
$vmPasswordPlainText | clip
mstsc /v:$($result.outputs.vmFQDN.value) /f
```

### Test

```powershell
start "https://$domain"
start "https://$($result.outputs.vmFQDN.value):8000"
#
curl "http://$domain" --verbose

#
curl "https://$domain" --verbose --insecure
curl "https://$($domain):8000" --verbose --insecure
curl "https://$($result.outputs.vmFQDN.value):8000" --verbose --insecure
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-vm-demo" -Force
```