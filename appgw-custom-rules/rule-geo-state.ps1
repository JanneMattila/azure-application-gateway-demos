Param (
    [Parameter(HelpMessage = "Resource group")]
    [string] $ResourceGroupName = "rg-appgw-custom-rules-demo",

    [Parameter(HelpMessage = "App Gateway WAF Policy name")]
    [string] $PolicyName = "waf-policy",

    [Parameter(HelpMessage = "Custom rule priority")]
    [int] $RulePriority = 50,
    
    [Parameter(Mandatory)]
    [ValidateSet('Enabled', 'Disabled')]
    [string] $State
)

$ErrorActionPreference = "Stop"

$policy = Get-AzApplicationGatewayFirewallPolicy -Name $PolicyName -ResourceGroupName $ResourceGroupName
$existingRule = $policy.CustomRules | Where-Object { $_.Priority -eq $RulePriority }
$existingRule
if ($null -eq $existingRule) {
    throw "Could not find existing custom rule with priority $RulePriority."
}

$existingRule.State = $State
Set-AzApplicationGatewayFirewallPolicy -InputObject $policy
