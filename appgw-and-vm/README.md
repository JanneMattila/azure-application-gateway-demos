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

Using openssl:

```bash
vm_ip="11.22.33.44"
```

```bash
openssl s_client -connect $vm_ip:443 -servername vm.demo.janne -showcerts -CAfile JanneCorpRootCA.cer
```

```console
CONNECTED(00000003)
depth=2 CN = JanneCorp Root CA
verify return:1
depth=1 CN = JanneCorp Intermediate certificate
verify return:1
depth=0 CN = vm.demo.janne
verify return:1
---
Certificate chain
 0 s:CN = vm.demo.janne
   i:CN = JanneCorp Intermediate certificate
-----BEGIN CERTIFICATE-----
MIIEXDCCAkSgAwIBAgIQHMb4Wk6+jbxJGDFnEswDgTANBgkqhkiG9w0BAQsFADAt
x2ooDAW8OnfzOoiNJaPluw==
-----END CERTIFICATE-----
 1 s:CN = JanneCorp Intermediate certificate
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgIQe7pGLtY+r6hJFzzPqTXlozANBgkqhkiG9w0BAQsFADAc
Rp3tqaTm9sC25LvFQi0d9xguRzWPYKG4M+Sg
-----END CERTIFICATE-----
---
Server certificate
subject=CN = vm.demo.janne

issuer=CN = JanneCorp Intermediate certificate

---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: ECDH, P-384, 384 bits
---
SSL handshake has read 3144 bytes and written 755 bytes
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
    Session-ID: DF891C57AFBC8F5AE9B9C0894C8C1321587E8243B6866BF3B66881F8C0A3F099
    Session-ID-ctx:
    Resumption PSK: E6D112BB9BCEE55D7E8FF05EDB04F4D6F7730714C75626CF97A3A5AB816783A47081E1411554F400020D5F751FE77038
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 36000 (seconds)
    TLS session ticket:
    0000 - b6 08 00 00 05 32 8a d5-7e 66 8a e0 66 e9 87 cb   .....2..~f..f...
    0010 - 63 c7 8e ef 3a 0d 29 f7-73 9d f3 ea d6 de c3 68   c...:.).s......h

    Start Time: 1712833561
    Timeout   : 7200 (sec)
    Verify return code: 0 (ok)
    Extended master secret: no
    Max Early Data: 0
```

```bash
openssl s_client -connect $vm_ip:443 -servername vm.demo.janne -showcerts -verify 4 -verify_return_error -CAfile JanneCorpRootCA.cer
openssl s_client -connect $vm_ip:8000 -servername vm.demo.janne -showcerts -verify 4 -verify_return_error -CAfile JanneCorpRootCA.cer
```

```bash
openssl s_client -connect $vm_ip:8000 -servername vm.demo.janne -showcerts -CAfile JanneCorpRootCA.cer
```

```console
CONNECTED(00000003)
depth=2 CN = JanneCorp Root CA
verify return:1
depth=1 CN = JanneCorp Intermediate certificate
verify return:1
depth=0 CN = vm.demo.janne
verify return:1
---
Certificate chain
 0 s:CN = vm.demo.janne
   i:CN = JanneCorp Intermediate certificate
-----BEGIN CERTIFICATE-----
MIIEXDCCAkSgAwIBAgIQHMb4Wk6+jbxJGDFnEswDgTANBgkqhkiG9w0BAQsFADAt
x2ooDAW8OnfzOoiNJaPluw==
-----END CERTIFICATE-----
 1 s:CN = JanneCorp Intermediate certificate
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFVzCCAz+gAwIBAgIQe7pGLtY+r6hJFzzPqTXlozANBgkqhkiG9w0BAQsFADAc
Rp3tqaTm9sC25LvFQi0d9xguRzWPYKG4M+Sg
-----END CERTIFICATE-----
 2 s:CN = JanneCorp Root CA
   i:CN = JanneCorp Root CA
-----BEGIN CERTIFICATE-----
MIIFIzCCAwugAwIBAgIQIOsFjS+996tEsVVGXO9Y+jANBgkqhkiG9w0BAQsFADAc
nN4anJ1qgHVmH6AXBimoDSRuKXVnkq0=
-----END CERTIFICATE-----
---
Server certificate
subject=CN = vm.demo.janne

issuer=CN = JanneCorp Intermediate certificate

---
No client certificate CA names sent
Peer signing digest: SHA256
Peer signature type: RSA-PSS
Server Temp Key: X25519, 253 bits
---
SSL handshake has read 4376 bytes and written 385 bytes
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
    Session-ID: 9CC6D82BC4DD350D6DE1E799D54D18EC9A58CE5F0299D3AB925EF9A1C14D4F55
    Session-ID-ctx:
    Resumption PSK: 4163D37A297B0DF3AA3BFA2DC38857C47C6E36DED69FD5FEBF196C0485B9836600DBD43056EFA72FB22A0CC79C6C1023
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 7200 (seconds)
    TLS session ticket:
    0000 - 8e 9c 66 ff 9c 3e 21 48-46 8f 32 da 29 3a 0f e6   ..f..>!HF.2.):..
    0010 - fe da f7 f3 f5 cf 11 c6-85 48 3c 24 2f 4a 39 81   .........H<$/J9.
    0020 - 7e 6b d7 b8 c0 ce b4 06-7a db 03 f0 28 e7 a2 5b   ~k......z...(..[
    0030 - 7b ec ef 54 ee 4a 1d ef-21 0a 3b f2 ef 82 70 f5   {..T.J..!.;...p.
    0040 - 27 b2 00 1a 96 77 6a 0e-10 bd 87 17 a3 ed 9e e0   '....wj.........
    0050 - 0c aa 74 16 04 89 c6 ba-87 5d 17 f8 54 c0 ce 70   ..t......]..T..p
    0060 - 1b 3b 2d a4 29 53 9e 9f-f8 e0 56 a0 1e 36 e5 f0   .;-.)S....V..6..
    0070 - 4e 8f 78 be 94 7e ea ab-94 98 f2 03 12 5e 6a 32   N.x..~.......^j2
    0080 - 0f 9f 48 c2 87 73 54 ff-b6 69 31 a0 ee 7a 16 bc   ..H..sT..i1..z..
    0090 - c5 f9 63 fc eb 82 2e a7-c4 02 43 b7 30 3c 64 e6   ..c.......C.0<d.
    00a0 - b8 28 b0 8c 55 2d bb 5e-1a c8 ee 0e a8 82 75 08   .(..U-.^......u.
    00b0 - f2 4f 14 98 a1 76 b3 31-a7 90 c0 86 d9 06 c2 dd   .O...v.1........
    00c0 - eb 92 06 2f 86 ca 06 01-51 73 ac df cd 26 99 cd   .../....Qs...&..
    00d0 - 2b 40 d8 e0 4e ba 20 51-0d 30 e8 ef 8b c5 df ec   +@..N. Q.0......
    00e0 - 93 39 a0 1a 7b 5e b7 ff-2a 21 45 2a 26 0f a7 26   .9..{^..*!E*&..&

    Start Time: 1712833718
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
    Session-ID: 3E2F6A5DB4304DCF236BE3C3F17CD64E6720E2E5033BC5BEF429E7981E12047D
    Session-ID-ctx:
    Resumption PSK: 8ABE044930DE53BAE4A443D89810FB6D0B1144E0BBD16725B04DEB8A3824BBDE35EC51DB2D0D3A6EE551474619EDE7E5
    PSK identity: None
    PSK identity hint: None
    SRP username: None
    TLS session ticket lifetime hint: 7200 (seconds)
    TLS session ticket:
    0000 - 8e 9c 66 ff 9c 3e 21 48-46 8f 32 da 29 3a 0f e6   ..f..>!HF.2.):..
    0010 - 12 fe d8 0b c8 46 35 6c-89 48 f6 3e 18 aa 31 30   .....F5l.H.>..10
    0020 - 17 e7 9c 65 a9 33 62 5d-a6 b6 54 41 16 98 cb 6c   ...e.3b]..TA...l
    0030 - b5 1e 6f cc 0d 7e bd 1c-4c dc 8a bc ad 64 f9 57   ..o..~..L....d.W
    0040 - 38 92 85 50 b5 05 0c e3-21 54 67 c3 f3 0a e0 00   8..P....!Tg.....
    0050 - e4 f2 81 7e 97 d3 ea 0f-4f 8b 5c f5 47 a1 1c f7   ...~....O.\.G...
    0060 - d1 12 ea ff 29 37 0a 3d-32 04 d3 da 60 86 a7 53   ....)7.=2...`..S
    0070 - cd 25 77 4c 7f cf b0 b8-9a 6d 40 7c 41 f5 82 42   .%wL.....m@|A..B
    0080 - 62 f6 7d d4 b5 ce ae bb-7b ce be ea 44 f1 bc 59   b.}.....{...D..Y
    0090 - 24 4f 8e f6 2a e3 17 75-d2 51 45 1e 91 4c 15 89   $O..*..u.QE..L..
    00a0 - 96 b4 2f d1 8d 9c 25 a9-b2 cc 32 b1 51 e2 29 e4   ../...%...2.Q.).
    00b0 - ca 91 ac ff b9 b4 88 e7-b8 65 c2 73 5a b6 eb dc   .........e.sZ...
    00c0 - d6 f1 03 36 bd ea 0a 10-f4 88 78 5f 4a 8c 13 00   ...6......x_J...
    00d0 - 93 0a 7b 9b 84 0c d8 c3-38 5e f2 85 f7 ab a2 5b   ..{.....8^.....[
    00e0 - fb 83 49 be c4 cf 44 d7-f4 70 d2 30 af bd e0 16   ..I...D..p.0....

    Start Time: 1712833718
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

### Testing outside VM

If Root CA certificate is not imported to the `Cert:\LocalMachine\Root`, you will get error like this:

```console
$ curl https://vm.demo.janne --resolve "vm.demo.janne:443:$($vm_ip)" --verbose --ca-native
* Added vm.demo.janne:443:11.22.33.44 to DNS cache
* Hostname vm.demo.janne was found in DNS cache
*   Trying 11.22.33.44:443...
* Connected to vm.demo.janne (11.22.33.44) port 443
* schannel: disabled automatic use of client certificate
* ALPN: curl offers http/1.1
* schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
* Closing connection
* schannel: shutting down SSL/TLS connection with vm.demo.janne port 443
curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325) - The certificate chain was issued by an authority that is not trusted.
More details here: https://curl.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

After importing them:

```powershell
Import-Certificate -FilePath JanneCorpRootCA.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath IntermediateCertificate.cer -CertStoreLocation Cert:\LocalMachine\CA
```

You will get:

```console
$ curl https://vm.demo.janne --resolve "vm.demo.janne:443:$($vm_ip)" --verbose --ca-native --ssl-no-revoke
* Added vm.demo.janne:443:11.22.33.44 to DNS cache
* Hostname vm.demo.janne was found in DNS cache
*   Trying 11.22.33.44:443...
* Connected to vm.demo.janne (11.22.33.44) port 443
* schannel: disabled automatic use of client certificate
* ALPN: curl offers http/1.1
* ALPN: server accepted http/1.1
* using HTTP/1.1
> GET / HTTP/1.1
> Host: vm.demo.janne
> User-Agent: curl/8.4.0
> Accept: */*
>
* schannel: remote party requests renegotiation
* schannel: renegotiating SSL/TLS connection
* schannel: SSL/TLS connection renegotiated
< HTTP/1.1 200 OK
< Content-Type: text/html
< Last-Modified: Thu, 11 Apr 2024 09:10:02 GMT
< Accept-Ranges: bytes
< ETag: "88838a9f08bda1:0"
< Server: Microsoft-IIS/10.0
< Date: Thu, 11 Apr 2024 12:02:57 GMT
< Content-Length: 703
<
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
// abbreviated
</body>
</html>* Connection #0 to host vm.demo.janne left intact
```

Same output from port 8000:

```console
$ curl https://vm.demo.janne:8000 --resolve "vm.demo.janne:8000:$($vm_ip)" --verbose --ca-native --ssl-no-revoke
* Added vm.demo.janne:8000:11.22.33.44 to DNS cache
* Hostname vm.demo.janne was found in DNS cache
*   Trying 11.22.33.44:8000...
* Connected to vm.demo.janne (11.22.33.44) port 8000
* schannel: disabled automatic use of client certificate
* ALPN: curl offers http/1.1
* ALPN: server accepted http/1.1
* using HTTP/1.1
> GET / HTTP/1.1
> Host: vm.demo.janne:8000
> User-Agent: curl/8.4.0
> Accept: */*
>
* schannel: remote party requests renegotiation
* schannel: renegotiating SSL/TLS connection
* schannel: SSL/TLS connection renegotiated
* schannel: remote party requests renegotiation
* schannel: renegotiating SSL/TLS connection
* schannel: SSL/TLS connection renegotiated
< HTTP/1.1 200 OK
< Date: Thu, 11 Apr 2024 12:04:30 GMT
< Connection: keep-alive
< Keep-Alive: timeout=5
< Transfer-Encoding: chunked
<
Node App
* Connection #0 to host vm.demo.janne left intact
```

### Clean up

```powershell
Remove-AzResourceGroup -Name "rg-appgw-vm-demo" -Force
```
