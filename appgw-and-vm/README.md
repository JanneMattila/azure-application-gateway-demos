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
  -CertStoreLocation "cert:\CurrentUser\My" `
  -NotAfter (Get-Date).AddYears(20) `
  -HashAlgorithm sha256 -KeyLength 4096 `
  -KeyExportPolicy Exportable `
  -KeyUsageProperty All `
  -KeyUsage CertSign, CRLSign, DigitalSignature `
  -TextExtension @("2.5.29.19={text}CA=1")

# To find existing Root CA
$rootCA = Get-ChildItem -Path cert:\CurrentUser\my | Where-Object { $_.Subject -eq "CN=JanneCorp Root CA" }
$rootPassword = ConvertTo-SecureString -String "1234" -Force -AsPlainText

Get-ChildItem -Path cert:\CurrentUser\my\$($rootCA.Thumbprint) | 
  Export-PfxCertificate -FilePath JanneCorpRootCA.pfx -Password $rootPassword

# To find existing Intermediate Certificate
$intermediateCertificate = Get-ChildItem -Path cert:\CurrentUser\my | Where-Object { $_.Subject -eq "CN=JanneCorp Intermediate certificate" }

# Create Intermediate Certificate
$intermediateCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\CurrentUser\my `
  -Subject "JanneCorp Intermediate certificate" `
  -FriendlyName "JanneCorp Intermediate certificate" `
  -Signer $rootCA `
  -NotAfter (Get-Date).AddYears(20) `
  -HashAlgorithm sha256 -KeyLength 4096 `
  -KeyExportPolicy Exportable `
  -KeyUsageProperty All `
  -KeyUsage CertSign, CRLSign, DigitalSignature `
  -TextExtension @("2.5.29.19={text}CA=1")

$intermediatePassword = ConvertTo-SecureString -String "2345" -Force -AsPlainText

Get-ChildItem -Path cert:\CurrentUser\my\$($intermediateCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath IntermediateCertificate.pfx -Password $intermediatePassword -ChainOption BuildChain

# To find existing AppGw Certificate
$appGwCertificate = Get-ChildItem -Path cert:\CurrentUser\my | Where-Object { $_.Subject -eq "CN=$domain" }

# Create AppGw Certificate
$appGwCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\CurrentUser\my `
  -DnsName $domain `
  -Signer $intermediateCertificate `
  -NotAfter (Get-Date).AddYears(20)

$appGwPassword = ConvertTo-SecureString -String "3456" -Force -AsPlainText

Get-ChildItem -Path cert:\CurrentUser\my\$($appGwCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath AppGw.pfx -Password $appGwPassword -ChainOption BuildChain

# Create VM Certificate using the same Intermediate Certificate
$vmCertificate = New-SelfSignedCertificate `
  -CertStoreLocation cert:\CurrentUser\my `
  -DnsName "vm.demo.janne" `
  -HashAlgorithm sha256 -KeyLength 2048 -KeyExportPolicy Exportable `
  -Signer $intermediateCertificate `
  -NotAfter (Get-Date).AddYears(20)

$vmCertificatePassword = ConvertTo-SecureString -String "4567" -Force -AsPlainText

Get-ChildItem -Path cert:\CurrentUser\my\$($vmCertificate.Thumbprint) | 
  Export-PfxCertificate -FilePath vm.pfx -Password $vmCertificatePassword -ChainOption BuildChain

# Create VM Certificate using the Root CA
$vmCertificate2 = New-SelfSignedCertificate `
  -CertStoreLocation cert:\CurrentUser\my `
  -DnsName "vm.demo.janne" `
  -HashAlgorithm sha256 -KeyLength 2048 -KeyExportPolicy Exportable `
  -Signer $rootCA `
  -NotAfter (Get-Date).AddYears(20)

$vmCertificatePassword = ConvertTo-SecureString -String "4567" -Force -AsPlainText

Get-ChildItem -Path cert:\CurrentUser\my\$($vmCertificate2.Thumbprint) | 
  Export-PfxCertificate -FilePath vm2.pfx -Password $vmCertificatePassword -ChainOption BuildChain
```

### Convert pfx to CER and PEM

[Converting pfx to pem using openssl](https://stackoverflow.com/questions/15413646/converting-pfx-to-pem-using-openssl)

From [Troubleshoot backend health issues in Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/application-gateway-backend-health-troubleshooting#the-intermediate-certificate-was-not-found)

> This chain **must start with the Leaf Certificate**,
> then **the Intermediate certificate(s)**,
> and **finally, the Root CA certificate**

```bash
rootPassword="1234"
intermediatePassword="2345"
vmCertificatePassword="4567"

openssl pkcs12 -in JanneCorpRootCA.pfx -clcerts -nokeys -out JanneCorpRootCA.cer -nodes -passin pass:$rootPassword

openssl pkcs12 -in IntermediateCertificate.pfx -clcerts -nokeys -out IntermediateCertificateOnly.cer -nodes -passin pass:$intermediatePassword
cat IntermediateCertificateOnly.cer JanneCorpRootCA.cer > IntermediateCertificate.cer

# Convert the intermediate certificate created VM certificate to PEM
openssl pkcs12 -in vm.pfx -out vm_key.pem -nocerts -nodes -passin pass:$vmCertificatePassword
openssl pkcs12 -in vm.pfx -clcerts -nokeys -out vm_certOnly.pem -nodes -passin pass:$vmCertificatePassword
cat vm_certOnly.pem IntermediateCertificateOnly.cer JanneCorpRootCA.cer > vm_cert.pem

# Convert the Root CA created VM certificate to PEM
openssl pkcs12 -in vm2.pfx -out vm_key2.pem -nocerts -nodes -passin pass:$vmCertificatePassword
openssl pkcs12 -in vm2.pfx -clcerts -nokeys -out vm_certOnly2.pem -nodes -passin pass:$vmCertificatePassword
cat vm_certOnly2.pem JanneCorpRootCA.cer > vm_cert2.pem
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
curl "https://$domain" --verbose
curl "https://$domain" --verbose --insecure
curl "https://$($domain):8000" --verbose --insecure
curl "https://$($result.outputs.vmFQDN.value):8000" --verbose --insecure
```

```bash
targetip="4.225.196.161"
openssl s_client -connect $targetip:443 -servername vm.demo.janne -showcerts -CAfile JanneCorpRootCA.cer
```

```console
CONNECTED(00000003)
depth=2 CN = JanneCorp Root CA
verify return:1
depth=1 CN = JanneCorp Intermediate certificate
verify return:1
depth=0 CN = contoso0000000005.swedencentral.cloudapp.azure.com
verify return:1
---
Certificate chain
 0 s:CN = contoso0000000005.swedencentral.cloudapp.azure.com
   i:CN = JanneCorp Intermediate certificate
-----BEGIN CERTIFICATE-----
MIIEpjCCAo6gAwIBAgIQPXes5LmH4rVNEr6sGo4K2jANBgkqhkiG9w0BAQsFADAt
MSswKQYDVQQDDCJKYW5uZUNvcnAgSW50ZXJtZWRpYXRlIGNlcnRpZmljYXRlMB4X
DTI0MDQxMTA4MjgxNloXDTQ0MDQxMTA4MzgxNlowPTE7MDkGA1UEAwwyY29udG9z
bzAwMDAwMDAwMDUuc3dlZGVuY2VudHJhbC5jbG91ZGFwcC5henVyZS5jb20wggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMxvZgv/Gsz3vsxbvGY4re7FbL
YfPaH58FRDZxnHhuf6D6YPjRq6uex/iAL93+oY+xlzL8e5YfrImmWpLVjUpNxvZB
YWxndQjLebK1waxCfceqEOcekixS2qOleCs1ubvXvRQRUZ3a5jz+gi/sglQo3K4Y
RwWtieUT2XyQW/QqJ2FXNrfoQUFRw8oLlNNjIv22zi6OWcVeQRXMxXHrTfEn1JQG
yvhjrtoM8C29EMx3a+71ZHMbt3rEa+EV041ELUkQymM5067bxrfC6igUeTailTGB
KHut/OsMK79x/0C2PDA2lIibLrA9eeGYO0vzFDXkgacAy8MhxHUKQv/qDoG5AgMB
AAGjgbEwga4wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggr
BgEFBQcDATA9BgNVHREENjA0gjJjb250b3NvMDAwMDAwMDAwNS5zd2VkZW5jZW50
cmFsLmNsb3VkYXBwLmF6dXJlLmNvbTAfBgNVHSMEGDAWgBTmYyV/clXMxRmhWT2C
y2gnSnH6cTAdBgNVHQ4EFgQUL3xPZumQbmRGbXnISaHmIZfE014wDQYJKoZIhvcN
AQELBQADggIBAGH4Fr8/sTNwex7fpOJSRigav7SL8bU0L/4YmmSMw05ddWGpf6bb
yfFHq5Z5VT5uZDOaiUicz1ZNy/0CROnYv26JL3tGMxDCSdOFZDwsfVdBT4rRDmCe
di41qgBRmUmN6pzddqUXJabjPImDutC50dtdu/uqmzb4rkakHMHLFlgVXKfbLGxo
NREO+APCS8+wlhLs1wqsxfYQPrCArtPye8/JkJ3tIFBxFCDl34MArQ/unlOPP4cA
9Q+vwnEDpDrgQkILgungcUFyKzAty4SFq3LG1pbJKOx1D3ck51Vf2l/usyIlS9aK
SaERGgx0BPuP0UiMl1GNKWZc17lNLaGAFWBwNYyJXW6FKj41ZA2EO985nx/5JN9u
ekTq86pLHXKXeGH65LbS2aMUFI5bgwLzmEMCEmOnuTkqVF/cqpm04DprqP2vKtw/
qXaAcMv0jRjBg3vRgGPDyMAvkaC+Kp3kroVEx5VUuABqV30Z8KFmxdE1Gyo9If88
y6BJ0bydECkh/HqqcsERDF+yrQwfVZ8sKzo1NIvGWB2iEP4Qvnm6I80t/jfj4P/t
/3d/gY4Ppjb6QjPtqVryN4CXd7AscxtQktRONPvVmkLTIqIJNKAHXZHteanVkI68
8QIJeIPofddFYFm6Q8m7ar13+kVmiR/yC/011vN/JQRIsyqWmDao8dnu
-----END CERTIFICATE-----
 1 s:CN = JanneCorp Root CA
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFIzCCAwugAwIBAgIQIOsFjS+996tEsVVGXO9Y+jANBgkqhkiG9w0BAQsFADAc
MRowGAYDVQQDDBFKYW5uZUNvcnAgUm9vdCBDQTAeFw0yNDA0MTEwODI2MjRaFw00
NDA0MTEwODM2MjNaMBwxGjAYBgNVBAMMEUphbm5lQ29ycCBSb290IENBMIICIjAN
BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwi4hjFu6QL+jv5ZzkSgvRaae02tT
eruoFq+dQiMbq4gooM6L/WZPdA7/zKyhRbxr645bbt7ah9za09mpXEVGW9m0wLp0
lmAB2ibcln8VRa4OJSTD3KjtbYwkopfUiw+75Y/zWhkvXgYYWCLay2+wsYxJlNFr
FLDa2Q4/hQG4FRLn3Vtq0K1BFR+YSBWv4V+aM5aoE7UahMcjipfsrGJUgKgMS8n+
/XJ/LZMYmdP5y/Nrm5keeMx0gg7XxkZWnkqu+bbQKo4t0Qj6U/ml3AJmfHqtvID3
erxwEZRu+D7tTajcuUIdiC8QJp/+yj59GJLXLCzbTfMx/HuZFrmNXBLQxOlxJYPk
DRZYghW9SE6mGKlGHLp4isOfXTNdV2AOOOItt61Q3XjZxF8Xr3xj7ix1sr74VMIE
fSDmP5LEJspBviywS5qYlLev0TSA1kbGVTm9W/HRemLVxF41OP54GHneMZ7OPn8M
Od8EryaIFzOkqI8GFNxRL/JRXLN780Ac+g2ZQ64ITLYzmZKoAXjaaP2QZX4sucg1
ceU1bagCYYY7IcX2WZjj/PrfkjpQt7aHEFReSzFcllcRpcuRydx2Yz34x9ycwuFe
mo4cadAov9oBFQmLo/RcVHGRNgaGGEIHNdYSsrZ9mE2nNGrcojjXr0dg2WnT43X4
vJ9eukurMYeiqT0CAwEAAaNhMF8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdJQQWMBQG
CCsGAQUFBwMCBggrBgEFBQcDATAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSg
YNh/TbFTjqxox7lNrFW8WFs46zANBgkqhkiG9w0BAQsFAAOCAgEAWkNpoJxnkOOA
OcmnFaUB4feOrspvP06qF9wKhaow4TFPYHeW6lgHjdkLqGjKLffeUh3J3buKEGEq
LfrlZRcFlpOmxlV8BCNCiwsDs4E41py7JbEovu3s8ixvTDXp7zU46qx+DPB+MI0i
asEiXxRQkF5ThTI7uf7BN4evHsLna9S/y7fUdgkIxAxZtKYMe7loFXc4zV84+hBk
+FjCX6Xg6V70onZ2FqFEXAm9EL79NOOSK6SiUn+fn4NJe19qwTsMxV/HCHikb5Nv
QdaUZo88NcKuxxwtBg5tNLWmG/pK7oagQNbdbEPBOx5zw5Tz2dmsG8g3otkhmSMA
SgARYd1xSY9iTAGCgn90mDwEp8bbRMJpzKFKdbXHbUl9NjZvb9k2O1qMEWYc+nUF
2jsG5yQlO8DaMMwcLXyRwf1UzdtqG8Sn25uZwX/JK4raLpiPb+aTwyNy0VRtcdYo
UqV6o1d3+XFaao2Bo3Dl+UnupcSLamRriWcdy2RTE8l8iiwYuU8fF2IAXcRqyZgu
Uu0Baxi8PR7HOAhBtK8/tNTW4P4zE0U5/G6hjv+Q338wi8edHIYnGSjOraTVYUMU
RYGUXadiDcxHCN4Puruwh8XCdbHLg8IhIyQGfH3bTAXNAeZpsp94SBl6+H2kRTKf
nN4anJ1qgHVmH6AXBimoDSRuKXVnkq0=
-----END CERTIFICATE-----
 2 s:CN = JanneCorp Intermediate certificate
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgIQe7pGLtY+r6hJFzzPqTXlozANBgkqhkiG9w0BAQsFADAc
MRowGAYDVQQDDBFKYW5uZUNvcnAgUm9vdCBDQTAeFw0yNDA0MTEwODI3MjRaFw00
NDA0MTEwODM3MjNaMC0xKzApBgNVBAMMIkphbm5lQ29ycCBJbnRlcm1lZGlhdGUg
Y2VydGlmaWNhdGUwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC8a+/O
dsvVXm37lIg8q13/JJlsh2djudFsY9tp6F5FOQgftz1Q4/oxcFNkY3fPIuNv0PEO
jiP019uNYmVIRKu8pk9OO3BDDa7jBorAQTpy4+Q5ne8kvZYSBqA7rapQASFkKoSa
m3Qz5p0HC/4iwP3gtCAY9L1oiZt8SLHcUqERZ9Qa47YgEeiCWwZIodlFGRldQRNC
45psRTRi9hlPN/FM5LZCeuhdteo2huFEOTCdH15p8LIDXJQv1KvUN2hkYD/gvxL3
Eea6nhhZXPktT9ohYT+f9GMoBlaXr2hMNRO84Q5nzq8Coc+H4pg/nNUhPat3U1Ue
mzxNHwrHLfFdKKhLmX4MeBRaOd2Q8irqxhavd4Y7boVPM0ZAapUj3Yp7114f5ve0
WKqeKNIKvgYxd6GfdrqmH+Dc6eJxepyxLBE0FAU6k3n/MMC+cHhwIQXK2m1SN7Qe
Fqviv9pSJmH9REQ7UzJZOJWxjh6aPlHm14l5huBJguBPHKRxAGDgdOR/ofiHXN/W
rX9561T/F5qNcYjSRmK8vPngJPmbDXQQtSCLHe+okNsOjpXRdm0GJS/XFAWJPLj+
EqB5u1zfzkjSuK26WL2KPinWQjoPG4EoOMi6sxP8srWfVfEomQqFSWOaJ+Si8uQS
aVUjIuX6dvN+FIHw3t8GcBzcEfd0eFX1FcnhiQIDAQABo4GDMIGAMA4GA1UdDwEB
/wQEAwIBhjAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYBBQUHAwEwDwYDVR0TAQH/
BAUwAwEB/zAfBgNVHSMEGDAWgBSgYNh/TbFTjqxox7lNrFW8WFs46zAdBgNVHQ4E
FgQU5mMlf3JVzMUZoVk9gstoJ0px+nEwDQYJKoZIhvcNAQELBQADggIBAD0A14SI
4GJhYsermZzlB0EIFEX7DqyTC5DrsHSCShwudHd5nBxXwRD4aDnRRV6LeEZACFqL
HCVZLbWjOGllyAY2bB/MiVyCs1YVCFZ09rs3mSauoMXL53szrX3sm68SM2+KD6mh
cydAWI/eFiAOhChH9KONvxSZJHE+IrO3qkmTJOW8KGLTM6qRpKh7WWmopgg1fcMu
6onLMfKiTcdJGwLrInmxRUFc6pyBZ9slQQ2wrDBISMzBUD0LxgOHEI2ShjwpfPcc
B23lapxVtKG4RfzLetHUERK9ctRvV7cx1n15B5DxxaVFsxSnZKCZcjELURuCXxSP
SO2raSWFGEuF2EHiASk98CSmPLz5IryrHeh2yo2EHPnwLPUSAFS2vVrMVEs7o7bE
ZRcET9OxT6ID4hzS9qsAAVibCKNAiJhE60mrclvcXSrEMfTGlga+4h7swQeNddLb
HzNFYdX61LG45/1UBxRhqDfHr+O1KdyhVwiWBB9bx1+zNFiB52W+1mt3redRoA5D
0SXpQZnDaR5UPGvRwfstxZP5EPRZOuWP4+GRmGxevZIZypJIDiau6qj/p7lsMroP
oy01SMBsUAWQs7x5ttKPU3gQDbs/DS2+w65CiugTXZlYAQon3RpKILd5mTwf5qto
Rp3tqaTm9sC25LvFQi0d9xguRzWPYKG4M+Sg
-----END CERTIFICATE-----
---
Server certificate
subject=CN = contoso0000000005.swedencentral.cloudapp.azure.com

issuer=CN = JanneCorp Intermediate certificate

---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 4454 bytes and written 385 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
---
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: 3C60702852586CC3135DC3E385A4DE3A0CF7925B16D1A72C276313B920211D64
    Session-ID-ctx:
    Resumption PSK: 40580E8D495DA135006B26024D2D30E0FD604A4AB68CBD54033B828E08423B44F98976D7C96B3A60F397859D9A763149
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 300 (seconds)
    TLS session ticket:
    0000 - 89 e4 a3 b9 61 6b d7 14-fd d5 14 e7 2d 82 ec f7   ....ak......-...
    0010 - 3d 99 e1 e0 34 51 85 66-a9 3e 9d 5e a5 3c f4 a1   =...4Q.f.>.^.<..
    0020 - aa 8c ed 05 ab 5c f9 ec-58 55 fa cf f7 6f 3a 23   .....\..XU...o:#
    0030 - 03 31 7f 9a b6 4d 0d 7a-62 72 4f b2 62 9d fc 6d   .1...M.zbrO.b..m
    0040 - 87 54 96 90 b6 ca 74 80-1d 31 4a 2f 95 fb b3 75   .T....t..1J/...u
    0050 - bb e7 4c 7b 67 23 af b2-2e 12 37 d0 10 57 ff e5   ..L{g#....7..W..
    0060 - 27 c9 d3 fc 0b 4f 6a 97-6d f7 aa c6 77 70 3d 6f   '....Oj.m...wp=o
    0070 - 08 b5 ed 98 a4 14 24 f7-09 b6 0a 0e bc a5 67 3a   ......$.......g:
    0080 - 11 7c 76 5c ba da 13 74-44 57 0a 88 42 45 0b 03   .|v\...tDW..BE..
    0090 - 87 b7 da 2a 91 67 7d 4a-68 4b 72 4f 80 0b 2a 9b   ...*.g}JhKrO..*.
    00a0 - c7 58 a1 5e 4c 09 96 7a-e7 a9 68 f9 80 57 0b 7d   .X.^L..z..h..W.}
    00b0 - 96 3c cb 9b 9d a7 30 00-f8 68 e4 4c 19 30 91 26   .<....0..h.L.0.&
    00c0 - 55 1b d9 a9 f2 29 4d ae-08 ea 8a 01 53 8e 18 03   U....)M.....S...
    00d0 - 74 83 fa 01 69 6a 3f 9f-7c 28 30 f6 5c 89 e9 21   t...ij?.|(0.\..!
    00e0 - f7 c2 a2 22 f8 68 fb 91-d9 6f 1c 14 13 b5 00 c6   ...".h...o......

    Start Time: 1712831599
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: EF959AA168815CE9F626172270C856205F765E65EDE6EDA75E4FE9F568D29E63
    Session-ID-ctx:
    Resumption PSK: 61FB7242C4FA9C9E360D8123A1BE14C98F8E04B52475C44AFA740816AD8974996EAA5F8A7A4697C2DD675455A71F21A1
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 300 (seconds)
    TLS session ticket:
    0000 - 89 e4 a3 b9 61 6b d7 14-fd d5 14 e7 2d 82 ec f7   ....ak......-...
    0010 - e1 59 c7 40 a3 46 34 35-80 65 46 a2 b5 a7 e3 bc   .Y.@.F45.eF.....
    0020 - 50 23 42 b6 2f d5 1e b7-ed 37 18 2a e7 2d 5f 17   P#B./....7.*.-_.
    0030 - 2b 16 7f 00 5c 36 fb 9c-85 44 e0 75 aa 16 a0 0d   +...\6...D.u....
    0040 - 13 2f 56 b9 cc f5 ec 0b-b0 e9 fc 44 f4 13 4b 70   ./V........D..Kp
    0050 - 1a da 87 a1 99 17 b2 21-59 9e 7f b7 b4 1c 89 c0   .......!Y.......
    0060 - 22 79 10 07 9e cc ba d0-9e fa b2 d2 05 bb c6 26   "y.............&
    0070 - 84 1f ac 1a 56 e3 f7 65-d6 68 5b 75 a5 31 92 cf   ....V..e.h[u.1..
    0080 - 74 ba 02 84 4b 99 2b 50-6d ac 85 98 94 88 b4 0b   t...K.+Pm.......
    0090 - 08 69 78 2c 57 15 f3 2a-31 86 0e bb 20 03 c7 04   .ix,W..*1... ...
    00a0 - b0 0d f2 3c 30 8b db 50-04 8f 2c 2a 55 77 54 f8   ...<0..P..,*UwT.
    00b0 - 3e 59 99 1c 3e c9 eb fe-16 c0 51 9c b7 12 3f 81   >Y..>.....Q...?.
    00c0 - fd ac 75 21 67 4b f9 e3-32 2b d4 5e 09 0c 46 d4   ..u!gK..2+.^..F.
    00d0 - cd c7 a8 81 a9 38 d4 f4-c4 ea fd 64 33 5b ec 3e   .....8.....d3[.>
    00e0 - b3 51 72 11 9a 00 56 d5-fd 3a 79 d0 1f 64 42 d5   .Qr...V..:y..dB.

    Start Time: 1712831599
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
```

```bash
openssl s_client -connect $targetip:443 -servername vm.demo.janne -showcerts -verify 4 -verify_return_error -CAfile JanneCorpRootCA.cer
```

```console
verify depth is 4
CONNECTED(00000003)
depth=2 CN = JanneCorp Root CA
verify return:1
depth=1 CN = JanneCorp Intermediate certificate
verify return:1
depth=0 CN = contoso0000000005.swedencentral.cloudapp.azure.com
verify return:1
---
Certificate chain
 0 s:CN = contoso0000000005.swedencentral.cloudapp.azure.com
   i:CN = JanneCorp Intermediate certificate
-----BEGIN CERTIFICATE-----
MIIEpjCCAo6gAwIBAgIQPXes5LmH4rVNEr6sGo4K2jANBgkqhkiG9w0BAQsFADAt
MSswKQYDVQQDDCJKYW5uZUNvcnAgSW50ZXJtZWRpYXRlIGNlcnRpZmljYXRlMB4X
DTI0MDQxMTA4MjgxNloXDTQ0MDQxMTA4MzgxNlowPTE7MDkGA1UEAwwyY29udG9z
bzAwMDAwMDAwMDUuc3dlZGVuY2VudHJhbC5jbG91ZGFwcC5henVyZS5jb20wggEi
MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMxvZgv/Gsz3vsxbvGY4re7FbL
YfPaH58FRDZxnHhuf6D6YPjRq6uex/iAL93+oY+xlzL8e5YfrImmWpLVjUpNxvZB
YWxndQjLebK1waxCfceqEOcekixS2qOleCs1ubvXvRQRUZ3a5jz+gi/sglQo3K4Y
RwWtieUT2XyQW/QqJ2FXNrfoQUFRw8oLlNNjIv22zi6OWcVeQRXMxXHrTfEn1JQG
yvhjrtoM8C29EMx3a+71ZHMbt3rEa+EV041ELUkQymM5067bxrfC6igUeTailTGB
KHut/OsMK79x/0C2PDA2lIibLrA9eeGYO0vzFDXkgacAy8MhxHUKQv/qDoG5AgMB
AAGjgbEwga4wDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMCBggr
BgEFBQcDATA9BgNVHREENjA0gjJjb250b3NvMDAwMDAwMDAwNS5zd2VkZW5jZW50
cmFsLmNsb3VkYXBwLmF6dXJlLmNvbTAfBgNVHSMEGDAWgBTmYyV/clXMxRmhWT2C
y2gnSnH6cTAdBgNVHQ4EFgQUL3xPZumQbmRGbXnISaHmIZfE014wDQYJKoZIhvcN
AQELBQADggIBAGH4Fr8/sTNwex7fpOJSRigav7SL8bU0L/4YmmSMw05ddWGpf6bb
yfFHq5Z5VT5uZDOaiUicz1ZNy/0CROnYv26JL3tGMxDCSdOFZDwsfVdBT4rRDmCe
di41qgBRmUmN6pzddqUXJabjPImDutC50dtdu/uqmzb4rkakHMHLFlgVXKfbLGxo
NREO+APCS8+wlhLs1wqsxfYQPrCArtPye8/JkJ3tIFBxFCDl34MArQ/unlOPP4cA
9Q+vwnEDpDrgQkILgungcUFyKzAty4SFq3LG1pbJKOx1D3ck51Vf2l/usyIlS9aK
SaERGgx0BPuP0UiMl1GNKWZc17lNLaGAFWBwNYyJXW6FKj41ZA2EO985nx/5JN9u
ekTq86pLHXKXeGH65LbS2aMUFI5bgwLzmEMCEmOnuTkqVF/cqpm04DprqP2vKtw/
qXaAcMv0jRjBg3vRgGPDyMAvkaC+Kp3kroVEx5VUuABqV30Z8KFmxdE1Gyo9If88
y6BJ0bydECkh/HqqcsERDF+yrQwfVZ8sKzo1NIvGWB2iEP4Qvnm6I80t/jfj4P/t
/3d/gY4Ppjb6QjPtqVryN4CXd7AscxtQktRONPvVmkLTIqIJNKAHXZHteanVkI68
8QIJeIPofddFYFm6Q8m7ar13+kVmiR/yC/011vN/JQRIsyqWmDao8dnu
-----END CERTIFICATE-----
 1 s:CN = JanneCorp Root CA
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFIzCCAwugAwIBAgIQIOsFjS+996tEsVVGXO9Y+jANBgkqhkiG9w0BAQsFADAc
MRowGAYDVQQDDBFKYW5uZUNvcnAgUm9vdCBDQTAeFw0yNDA0MTEwODI2MjRaFw00
NDA0MTEwODM2MjNaMBwxGjAYBgNVBAMMEUphbm5lQ29ycCBSb290IENBMIICIjAN
BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAwi4hjFu6QL+jv5ZzkSgvRaae02tT
eruoFq+dQiMbq4gooM6L/WZPdA7/zKyhRbxr645bbt7ah9za09mpXEVGW9m0wLp0
lmAB2ibcln8VRa4OJSTD3KjtbYwkopfUiw+75Y/zWhkvXgYYWCLay2+wsYxJlNFr
FLDa2Q4/hQG4FRLn3Vtq0K1BFR+YSBWv4V+aM5aoE7UahMcjipfsrGJUgKgMS8n+
/XJ/LZMYmdP5y/Nrm5keeMx0gg7XxkZWnkqu+bbQKo4t0Qj6U/ml3AJmfHqtvID3
erxwEZRu+D7tTajcuUIdiC8QJp/+yj59GJLXLCzbTfMx/HuZFrmNXBLQxOlxJYPk
DRZYghW9SE6mGKlGHLp4isOfXTNdV2AOOOItt61Q3XjZxF8Xr3xj7ix1sr74VMIE
fSDmP5LEJspBviywS5qYlLev0TSA1kbGVTm9W/HRemLVxF41OP54GHneMZ7OPn8M
Od8EryaIFzOkqI8GFNxRL/JRXLN780Ac+g2ZQ64ITLYzmZKoAXjaaP2QZX4sucg1
ceU1bagCYYY7IcX2WZjj/PrfkjpQt7aHEFReSzFcllcRpcuRydx2Yz34x9ycwuFe
mo4cadAov9oBFQmLo/RcVHGRNgaGGEIHNdYSsrZ9mE2nNGrcojjXr0dg2WnT43X4
vJ9eukurMYeiqT0CAwEAAaNhMF8wDgYDVR0PAQH/BAQDAgGGMB0GA1UdJQQWMBQG
CCsGAQUFBwMCBggrBgEFBQcDATAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSg
YNh/TbFTjqxox7lNrFW8WFs46zANBgkqhkiG9w0BAQsFAAOCAgEAWkNpoJxnkOOA
OcmnFaUB4feOrspvP06qF9wKhaow4TFPYHeW6lgHjdkLqGjKLffeUh3J3buKEGEq
LfrlZRcFlpOmxlV8BCNCiwsDs4E41py7JbEovu3s8ixvTDXp7zU46qx+DPB+MI0i
asEiXxRQkF5ThTI7uf7BN4evHsLna9S/y7fUdgkIxAxZtKYMe7loFXc4zV84+hBk
+FjCX6Xg6V70onZ2FqFEXAm9EL79NOOSK6SiUn+fn4NJe19qwTsMxV/HCHikb5Nv
QdaUZo88NcKuxxwtBg5tNLWmG/pK7oagQNbdbEPBOx5zw5Tz2dmsG8g3otkhmSMA
SgARYd1xSY9iTAGCgn90mDwEp8bbRMJpzKFKdbXHbUl9NjZvb9k2O1qMEWYc+nUF
2jsG5yQlO8DaMMwcLXyRwf1UzdtqG8Sn25uZwX/JK4raLpiPb+aTwyNy0VRtcdYo
UqV6o1d3+XFaao2Bo3Dl+UnupcSLamRriWcdy2RTE8l8iiwYuU8fF2IAXcRqyZgu
Uu0Baxi8PR7HOAhBtK8/tNTW4P4zE0U5/G6hjv+Q338wi8edHIYnGSjOraTVYUMU
RYGUXadiDcxHCN4Puruwh8XCdbHLg8IhIyQGfH3bTAXNAeZpsp94SBl6+H2kRTKf
nN4anJ1qgHVmH6AXBimoDSRuKXVnkq0=
-----END CERTIFICATE-----
 2 s:CN = JanneCorp Intermediate certificate
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgIQe7pGLtY+r6hJFzzPqTXlozANBgkqhkiG9w0BAQsFADAc
MRowGAYDVQQDDBFKYW5uZUNvcnAgUm9vdCBDQTAeFw0yNDA0MTEwODI3MjRaFw00
NDA0MTEwODM3MjNaMC0xKzApBgNVBAMMIkphbm5lQ29ycCBJbnRlcm1lZGlhdGUg
Y2VydGlmaWNhdGUwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC8a+/O
dsvVXm37lIg8q13/JJlsh2djudFsY9tp6F5FOQgftz1Q4/oxcFNkY3fPIuNv0PEO
jiP019uNYmVIRKu8pk9OO3BDDa7jBorAQTpy4+Q5ne8kvZYSBqA7rapQASFkKoSa
m3Qz5p0HC/4iwP3gtCAY9L1oiZt8SLHcUqERZ9Qa47YgEeiCWwZIodlFGRldQRNC
45psRTRi9hlPN/FM5LZCeuhdteo2huFEOTCdH15p8LIDXJQv1KvUN2hkYD/gvxL3
Eea6nhhZXPktT9ohYT+f9GMoBlaXr2hMNRO84Q5nzq8Coc+H4pg/nNUhPat3U1Ue
mzxNHwrHLfFdKKhLmX4MeBRaOd2Q8irqxhavd4Y7boVPM0ZAapUj3Yp7114f5ve0
WKqeKNIKvgYxd6GfdrqmH+Dc6eJxepyxLBE0FAU6k3n/MMC+cHhwIQXK2m1SN7Qe
Fqviv9pSJmH9REQ7UzJZOJWxjh6aPlHm14l5huBJguBPHKRxAGDgdOR/ofiHXN/W
rX9561T/F5qNcYjSRmK8vPngJPmbDXQQtSCLHe+okNsOjpXRdm0GJS/XFAWJPLj+
EqB5u1zfzkjSuK26WL2KPinWQjoPG4EoOMi6sxP8srWfVfEomQqFSWOaJ+Si8uQS
aVUjIuX6dvN+FIHw3t8GcBzcEfd0eFX1FcnhiQIDAQABo4GDMIGAMA4GA1UdDwEB
/wQEAwIBhjAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYBBQUHAwEwDwYDVR0TAQH/
BAUwAwEB/zAfBgNVHSMEGDAWgBSgYNh/TbFTjqxox7lNrFW8WFs46zAdBgNVHQ4E
FgQU5mMlf3JVzMUZoVk9gstoJ0px+nEwDQYJKoZIhvcNAQELBQADggIBAD0A14SI
4GJhYsermZzlB0EIFEX7DqyTC5DrsHSCShwudHd5nBxXwRD4aDnRRV6LeEZACFqL
HCVZLbWjOGllyAY2bB/MiVyCs1YVCFZ09rs3mSauoMXL53szrX3sm68SM2+KD6mh
cydAWI/eFiAOhChH9KONvxSZJHE+IrO3qkmTJOW8KGLTM6qRpKh7WWmopgg1fcMu
6onLMfKiTcdJGwLrInmxRUFc6pyBZ9slQQ2wrDBISMzBUD0LxgOHEI2ShjwpfPcc
B23lapxVtKG4RfzLetHUERK9ctRvV7cx1n15B5DxxaVFsxSnZKCZcjELURuCXxSP
SO2raSWFGEuF2EHiASk98CSmPLz5IryrHeh2yo2EHPnwLPUSAFS2vVrMVEs7o7bE
ZRcET9OxT6ID4hzS9qsAAVibCKNAiJhE60mrclvcXSrEMfTGlga+4h7swQeNddLb
HzNFYdX61LG45/1UBxRhqDfHr+O1KdyhVwiWBB9bx1+zNFiB52W+1mt3redRoA5D
0SXpQZnDaR5UPGvRwfstxZP5EPRZOuWP4+GRmGxevZIZypJIDiau6qj/p7lsMroP
oy01SMBsUAWQs7x5ttKPU3gQDbs/DS2+w65CiugTXZlYAQon3RpKILd5mTwf5qto
Rp3tqaTm9sC25LvFQi0d9xguRzWPYKG4M+Sg
-----END CERTIFICATE-----
---
Server certificate
subject=CN = contoso0000000005.swedencentral.cloudapp.azure.com

issuer=CN = JanneCorp Intermediate certificate

---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 4454 bytes and written 385 bytes
Verification: OK
---
New, TLSv1.3, Cipher is TLS_AES_256_GCM_SHA384
Server public key is 2048 bit
Secure Renegotiation IS NOT supported
Compression: NONE
Expansion: NONE
No ALPN negotiated
Early data was not sent
Verify return code: 0 (ok)
---
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: DA1818A0C047AEF08AECFA55391CFA0B88218E70279AFE962E0627E7A4D08263
    Session-ID-ctx:
    Resumption PSK: 802AE1657600FD9C8B66A9BD7DB7F91A8CEC4D236DFB7171758BEB358548E943323BF73FCFD531A2FDAF78171C600851
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 300 (seconds)
    TLS session ticket:
    0000 - 89 e4 a3 b9 61 6b d7 14-fd d5 14 e7 2d 82 ec f7   ....ak......-...
    0010 - 2e dd e8 81 c6 62 16 76-39 db d2 66 4f 64 12 89   .....b.v9..fOd..
    0020 - 04 cd 0a 70 d3 e6 59 80-d6 f6 41 ee 5e ec eb 8f   ...p..Y...A.^...
    0030 - 8d 34 e7 15 08 9f c9 c8-b3 1a ed 70 b3 c7 3e ea   .4.........p..>.
    0040 - 66 83 6f d1 a4 cb f0 74-b3 13 0d cc 48 52 41 34   f.o....t....HRA4
    0050 - 45 3f 38 31 18 2c c9 fe-b7 6f 86 a1 61 5a 06 06   E?81.,...o..aZ..
    0060 - e0 4f 2e e3 5f 2d 1c 1a-a2 c5 81 46 c0 e0 50 dd   .O.._-.....F..P.
    0070 - 10 fc de 85 bc 32 20 aa-3c 99 80 8d a4 2a c3 5e   .....2 .<....*.^
    0080 - a5 36 31 05 89 1d 7f 81-da 53 a3 17 d7 f4 92 e1   .61......S......
    0090 - e8 1a fb b3 e1 fc ab f1-8a 63 ca b1 b2 d3 71 e4   .........c....q.
    00a0 - 78 33 bd c0 2f 12 f2 ba-fc 19 3b eb de 92 66 7e   x3../.....;...f~
    00b0 - fd 49 81 44 3f 17 a4 57-8b 8e 0a 54 33 af 20 77   .I.D?..W...T3. w
    00c0 - 6b 62 49 5c 3c 97 64 ba-75 ef 03 45 09 f9 16 2f   kbI\<.d.u..E.../
    00d0 - eb 72 27 8a 6b 7c fc 9d-88 03 bb 9a c6 62 d7 62   .r'.k|.......b.b
    00e0 - 36 85 59 1e 07 c3 6c ac-57 c9 0f 7c cb 48 ae 16   6.Y...l.W..|.H..

    Start Time: 1712831638
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
---
read R BLOCK
---
Post-Handshake New Session Ticket arrived:
SSL-Session:
    Protocol  : TLSv1.3
    Cipher    : TLS_AES_256_GCM_SHA384
    Session-ID: C0CAC2DA03F548E7F32DA4807949B2CD9CF9C04D268588DB75B7EEFE25012EBE
    Session-ID-ctx:
    Resumption PSK: 40B55EC1F2299ACA26B18177DF93532934BB481729A63EE9C1D2B9A7DD672253BDFFA3F21567AFE89DFC8D0D0BBEA674
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 300 (seconds)
    TLS session ticket:
    0000 - 89 e4 a3 b9 61 6b d7 14-fd d5 14 e7 2d 82 ec f7   ....ak......-...
    0010 - c2 61 dc fa be 51 6a 2b-55 1d a0 3f 20 bf f4 02   .a...Qj+U..? ...
    0020 - 1f 4f ba 21 ce e7 79 76-fe 6a a4 52 6a fd 6e b9   .O.!..yv.j.Rj.n.
    0030 - 5c 01 f4 c2 4f e3 77 a1-79 57 32 aa b9 10 fb 66   \...O.w.yW2....f
    0040 - b2 50 94 da 94 78 e5 ff-34 73 d4 31 66 dd 12 3b   .P...x..4s.1f..;
    0050 - 2f 94 86 d9 09 a2 83 88-c5 08 03 99 ca 21 a3 10   /............!..
    0060 - 58 67 f6 50 bb de cb 30-1c db 26 19 81 50 fd 71   Xg.P...0..&..P.q
    0070 - 5a 0d 8f a8 b3 5c 84 43-2b 3d 95 9b 86 a5 36 95   Z....\.C+=....6.
    0080 - 9b 5f 22 65 ed 47 e5 d3-65 6d fe 1a 7f 99 3c b7   ._"e.G..em....<.
    0090 - e7 26 57 d9 05 5c 31 67-2d 2f 1f 2b 42 e9 7f 48   .&W..\1g-/.+B..H
    00a0 - 18 78 65 52 e5 4d bc 8d-1d 6f a1 fd e0 89 71 ee   .xeR.M...o....q.
    00b0 - 54 7b 6d 59 ed 97 71 99-1a e3 03 8a 46 1e 6c 29   T{mY..q.....F.l)
    00c0 - 34 ed 5d aa c6 2b 25 0f-8e 5e 32 e1 06 82 ef b4   4.]..+%..^2.....
    00d0 - 14 4f 16 36 4d 2f 29 03-91 a2 09 d0 06 84 9a ee   .O.6M/).........
    00e0 - 57 02 09 29 16 81 3d 6c-cb 87 f8 5f e6 fe c4 41   W..)..=l..._...A

    Start Time: 1712831638
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
```

### Testing inside VM

If Root CA certificate is not imported to the `Cert:\LocalMachine\Root`, you will get error like this:

```console
$ ."C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl.exe" https://vm.demo.janne --verbose --ca-native
* Host vm.demo.janne:443 was resolved.
* IPv6: (none)
* IPv4: 10.0.1.4
*   Trying 10.0.1.4:443...
* Connected to vm.demo.janne (10.0.1.4) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* successfully imported Windows ROOT store
* successfully imported Windows CA store
*  CAfile: C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl-ca-bundle.crt
*  CApath: none
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Unknown (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (OUT), TLS alert, unknown CA (560):
* SSL certificate problem: unable to get local issuer certificate
* Closing connection
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

After importing it:

```powershell
Import-Certificate -FilePath \temp\JanneCorpRootCA.cer -CertStoreLocation Cert:\CurrentUser\Root
```

You will get:

```console
$ ."C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl.exe" https://vm.demo.janne --verbose --ca-native
* Host vm.demo.janne:443 was resolved.
* IPv6: (none)
* IPv4: 10.0.1.4
*   Trying 10.0.1.4:443...
* Connected to vm.demo.janne (10.0.1.4) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* successfully imported Windows ROOT store
* successfully imported Windows CA store
*  CAfile: C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl-ca-bundle.crt
*  CApath: none
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Unknown (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / [blank] / UNDEF
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=vm.demo.janne
*  start date: Apr 10 19:33:58 2024 GMT
*  expire date: Apr 10 19:43:58 2044 GMT
*  subjectAltName: host "vm.demo.janne" matched cert's "vm.demo.janne"
*  issuer: CN=JanneCorp Intermediate certificate
*  SSL certificate verify ok.
*   Certificate level 0: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 2: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://vm.demo.janne/
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: vm.demo.janne]
* [HTTP/2] [1] [:path: /]
* [HTTP/2] [1] [user-agent: curl/8.7.1]
* [HTTP/2] [1] [accept: */*]
> GET / HTTP/2
> Host: vm.demo.janne
> User-Agent: curl/8.7.1
> Accept: */*
>
< HTTP/2 200
< content-type: text/html
< last-modified: Thu, 11 Apr 2024 03:25:20 GMT
< accept-ranges: bytes
< etag: "9c1cee1bf8bda1:0"
< server: Microsoft-IIS/10.0
< date: Thu, 11 Apr 2024 06:18:29 GMT
< content-length: 703
<
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
// abbreviated
</html>* we are done reading and this is set to close, stop send
* Request completely sent off
* Connection #0 to host vm.demo.janne left intact
```

After importing intermediate certificate:

```powershell
Import-Certificate -FilePath \temp\IntermediateCertificate.cer -CertStoreLocation Cert:\CurrentUser\CA
```

You will get:

```console
$ ."C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl.exe" https://vm.demo.janne --verbose --ca-native
* Host vm.demo.janne:443 was resolved.
* IPv6: (none)
* IPv4: 10.0.1.4
*   Trying 10.0.1.4:443...
* Connected to vm.demo.janne (10.0.1.4) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* successfully imported Windows ROOT store
* successfully imported Windows CA store
*  CAfile: C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl-ca-bundle.crt
*  CApath: none
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Unknown (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / [blank] / UNDEF
* ALPN: server accepted h2
* Server certificate:
*  subject: CN=vm.demo.janne
*  start date: Apr 10 19:33:58 2024 GMT
*  expire date: Apr 10 19:43:58 2044 GMT
*  subjectAltName: host "vm.demo.janne" matched cert's "vm.demo.janne"
*  issuer: CN=JanneCorp Intermediate certificate
*  SSL certificate verify ok.
*   Certificate level 0: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
* using HTTP/2
* [HTTP/2] [1] OPENED stream for https://vm.demo.janne/
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:scheme: https]
* [HTTP/2] [1] [:authority: vm.demo.janne]
* [HTTP/2] [1] [:path: /]
* [HTTP/2] [1] [user-agent: curl/8.7.1]
* [HTTP/2] [1] [accept: */*]
> GET / HTTP/2
> Host: vm.demo.janne
> User-Agent: curl/8.7.1
> Accept: */*
>
* Request completely sent off
< HTTP/2 200
< content-type: text/html
< last-modified: Thu, 11 Apr 2024 03:25:20 GMT
< accept-ranges: bytes
< etag: "9c1cee1bf8bda1:0"
< server: Microsoft-IIS/10.0
< date: Thu, 11 Apr 2024 06:28:16 GMT
< content-length: 703
<
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
// abbreviated
</body>
</html>* Connection #0 to host vm.demo.janne left intact
```

Same output from port 8000:

```console
$ ."C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl.exe" https://vm.demo.janne:8000 --verbose --ca-native
* Host vm.demo.janne:8000 was resolved.
* IPv6: (none)
* IPv4: 10.0.1.4
*   Trying 10.0.1.4:8000...
* Connected to vm.demo.janne (10.0.1.4) port 8000
* ALPN: curl offers h2,http/1.1
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* successfully imported Windows ROOT store
* successfully imported Windows CA store
*  CAfile: C:\Temp\curl-8.7.1_7-win64-mingw\bin\curl-ca-bundle.crt
*  CApath: none
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.3 (IN), TLS handshake, Unknown (8):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / [blank] / UNDEF
* ALPN: server accepted http/1.1
* Server certificate:
*  subject: CN=vm.demo.janne
*  start date: Apr 11 08:28:27 2024 GMT
*  expire date: Apr 11 08:38:26 2044 GMT
*  subjectAltName: host "vm.demo.janne" matched cert's "vm.demo.janne"
*  issuer: CN=JanneCorp Intermediate certificate
*  SSL certificate verify ok.
*   Certificate level 0: Public key type ? (2048/112 Bits/secBits), signed using sha256WithRSAEncryption
*   Certificate level 1: Public key type ? (4096/128 Bits/secBits), signed using sha256WithRSAEncryption
* using HTTP/1.x
> GET / HTTP/1.1
> Host: vm.demo.janne:8000
> User-Agent: curl/8.7.1
> Accept: */*
>
* old SSL session ID is stale, removing
< HTTP/1.1 200 OK
< Date: Thu, 11 Apr 2024 09:42:58 GMT
< Connection: keep-alive
< Keep-Alive: timeout=5
< Transfer-Encoding: chunked
<
Node App
* Request completely sent off
* Connection #0 to host vm.demo.janne left intact
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-vm-demo" -Force
```
