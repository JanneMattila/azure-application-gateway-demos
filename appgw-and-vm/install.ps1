# Copy over the following files to the VM:
# - install.ps1 (this file)
# - server.js
# - package.json
# - vm.pfx
# - vm2.pfx
# - JanneCorpRootCA.cer
# - IntermediateCertificate.cer
# - vm_key.pem
# - vm_cert.pem

# Import the certificates
Import-Certificate -FilePath \temp\JanneCorpRootCA.cer -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath \temp\IntermediateCertificate.cer -CertStoreLocation Cert:\LocalMachine\CA

$CertificatePassword = "4567"
$secureStringPassword = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force
$certificate = Import-PfxCertificate -FilePath \temp\vm.pfx -CertStoreLocation Cert:\LocalMachine\My -Password $secureStringPassword
$certificate2 = Import-PfxCertificate -FilePath \temp\vm2.pfx -CertStoreLocation Cert:\LocalMachine\My -Password $secureStringPassword

# Add the certificate to the IIS
New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol "https"
# Add certificate created by intermediate CA
(Get-WebBinding -Name "Default Web Site" -Port 443 -Protocol "https").AddSslCertificate($certificate.Thumbprint, "my")
# Add certificate created by root CA
# (Get-WebBinding -Name "Default Web Site" -Port 443 -Protocol "https").AddSslCertificate($certificate2.Thumbprint, "my")

npm install

. "C:\Program Files\nodejs\node.exe" \temp\server.js
