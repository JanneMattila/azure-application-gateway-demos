Param (
    [Parameter(HelpMessage = "Deployment target resource group")]
    [string] $ResourceGroupName = "rg-appgw-redirect-demo",
    
    [Parameter(HelpMessage = "Custom domain name 1")]
    [string] $AppGwDomain = "contoso00000000090",

    [Parameter(HelpMessage = "Custom domain name 1")]
    [string] $CustomDomain1 = "myapp1.jannemattila.com",

    [Parameter(HelpMessage = "Custom domain name 2")]
    [string] $CustomDomain2 = "myapp2.jannemattila.com",

    [Parameter(HelpMessage = "Deployment location")]
    [string] $Location = "Sweden Central",

    [string] $Template = "main.bicep"
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
$additionalParameters['appGwDomain'] = $AppGwDomain
$additionalParameters['customDomain1'] = $CustomDomain1
$additionalParameters['customDomain2'] = $CustomDomain2

$result = New-AzResourceGroupDeployment `
    -DeploymentName $deploymentName `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $Template `
    @additionalParameters `
    -Mode Complete -Force `
    -Verbose

$result
