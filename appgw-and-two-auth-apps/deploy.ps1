Param (
    [Parameter(HelpMessage = "Deployment target resource group")]
    [string] $ResourceGroupName = "rg-appgw-auth-demo",

    [Parameter(HelpMessage = "Certificate password")]
    [securestring] $CertificatePassword,
    
    [Parameter(HelpMessage = "Client Id of Azure AD app")]
    [string] $ClientId,
    
    [Parameter(HelpMessage = "Client secret of Azure AD app")]
    [securestring] $ClientSecret,

    [Parameter(HelpMessage = "Client app tenant")]
    [string] $Authority,

    [Parameter(HelpMessage = "Deployment target resource group location")]
    [string] $Location = "North Europe",

    [string] $Template = "main.json"
)

$ErrorActionPreference = "Stop"

$date = (Get-Date).ToString("yyyy-MM-dd-HH-mm-ss")
$deploymentName = "Local-$date"

if ([string]::IsNullOrEmpty($env:RELEASE_DEFINITIONNAME)) {
    Write-Host (@"
Not executing inside Azure DevOps Release Management.
Make sure you have done "Login-AzAccount" and
"Select-AzSubscription -SubscriptionName name"
so that script continues to work correctly for you.
"@)
}
else {
    $deploymentName = $env:RELEASE_RELEASENAME
}

# Target deployment resource group
if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue)) {
    Write-Warning "Resource group '$ResourceGroupName' doesn't exist and it will be created."
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Verbose
}

# Additional parameters that we pass to the template deployment
$additionalParameters = New-Object -TypeName hashtable
$additionalParameters['certificatePassword'] = $CertificatePassword

$additionalParameters['clientId'] = $ClientId
$additionalParameters['clientSecret'] = $ClientSecret

if ($Authority.Length -gt 0) {
    # Default to current tenant
    $additionalParameters['authority'] = $Authority
}

$result = New-AzResourceGroupDeployment `
    -DeploymentName $deploymentName `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $Template `
    @additionalParameters `
    -Mode Complete -Force `
    -Verbose

$result
