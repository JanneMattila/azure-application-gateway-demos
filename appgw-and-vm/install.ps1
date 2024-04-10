New-Item \temp\ -ItemType Directory -Force
Set-Location \temp\

# Copy over:
# - server.js
# - vm.pfx

# Import the certificate
$CertificatePassword = "4567"
$secureStringPassword = ConvertTo-SecureString -String $CertificatePassword -AsPlainText -Force

$certificate = Import-PfxCertificate -FilePath \temp\vm.pfx -CertStoreLocation Cert:\LocalMachine\My -Password $secureStringPassword

# Install IIS
Install-WindowsFeature -name Web-Server -IncludeManagementTools

# Add the certificate to the IIS
$thumbprint = $certificate.Thumbprint

New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol "https"
(Get-WebBinding -Name "Default Web Site" -Port 443 -Protocol "https").AddSslCertificate($thumbprint, "my")

Invoke-WebRequest "https://nodejs.org/dist/v20.12.1/node-v20.12.1-x64.msi" -OutFile node.msi

msiexec.exe /i .\node.msi /qn

New-NetFirewallRule `
    -DisplayName "NodeApp" `
    -LocalPort 8000 `
    -Action Allow `
    -Profile 'Public' `
    -Protocol TCP `
    -Direction Inbound

. "C:\Program Files\nodejs\node.exe" \temp\server.js