Param (
    [Parameter(HelpMessage = "Resource group")]
    [string] $ResourceGroupName = "rg-appgw-custom-rules-demo",

    [Parameter(HelpMessage = "App Gateway WAF Policy name")]
    [string] $PolicyName = "waf-policy",

    [Parameter(HelpMessage = "Custom rule priority")]
    [int] $RulePriority = 40,
        
    [Parameter(Mandatory)]
    [ValidateSet('Standard_Verizon', 'Premium_Verizon', 'Custom_Verizon')]
    [string] $CDN
)

$ErrorActionPreference = "Stop"

# https://learn.microsoft.com/en-us/powershell/module/az.cdn/get-azcdnedgenode
$edgeNodes = Get-AzCdnEdgeNode | Where-Object { $_.Name -eq $CDN }
$edgeNodes

$IPs = New-Object -TypeName System.Collections.ArrayList
foreach ($addressGroup in $edgeNodes.IPAddressGroup) {
    foreach ($ip in $addressGroup.Ipv4Address) {
        $IPs.Add($ip.BaseIPAddress + "/" + $ip.PrefixLength)
    }
}

$IPs

if (0 -eq $IPs.Count) {
    "No IPs found with given query conditions. Removing rule."
}
else {
    $variable = New-AzApplicationGatewayFirewallMatchVariable -VariableName RemoteAddr
    $condition = New-AzApplicationGatewayFirewallCondition -MatchVariable $variable -Operator IPMatch -MatchValue $IPs
    $rule = New-AzApplicationGatewayFirewallCustomRule -Name AllowCdnIPs -Priority $RulePriority -RuleType MatchRule -MatchCondition $condition -Action Allow
    $rule
}

$policy = Get-AzApplicationGatewayFirewallPolicy -Name $PolicyName -ResourceGroupName $ResourceGroupName
$existingRule = $policy.CustomRules | Where-Object { $_.Priority -eq $RulePriority }
if ($null -ne $existingRule) {
    $policy.CustomRules.Remove($existingRule)
}

if (0 -ne $IPs.Count) {
    $policy.CustomRules.Add($rule)
}
$policy.CustomRules

Set-AzApplicationGatewayFirewallPolicy -InputObject $policy
