Param (
    [Parameter(HelpMessage = "Resource group")]
    [string] $ResourceGroupName = "rg-appgw-custom-rules-demo",

    [Parameter(HelpMessage = "Log Analytics Workspace")]
    [string] $WorkspaceName = "log-appgw",

    [Parameter(HelpMessage = "App Gateway WAF Policy name")]
    [string] $PolicyName = "waf-policy",

    [Parameter(HelpMessage = "Custom rule priority")]
    [int] $RulePriority = 80,

    [Parameter(HelpMessage = "Limit of the client HTTP Request")]
    [int] $RequestLimit = 100,
    
    [Parameter(HelpMessage = "Log search timeframe in minutes")]
    [int] $Minutes = 10,

    [Parameter(HelpMessage = "Log search timeframe in minutes")]
    [ValidateSet("Dedicated", "AzureDiagnostics")]
    [string] $LogDestinationType = "Dedicated"
)

$ErrorActionPreference = "Stop"

if ($LogDestinationType -eq "Dedicated") {
    # Use Resource specific table query
    $query = "AGWAccessLogs 
| where OperationName == 'ApplicationGatewayAccess' and
        TimeGenerated >= ago($($Minutes)min)
| summarize count() by ClientIp
| project IP=ClientIp, Requests=count_
| where Requests > $RequestLimit
| order by Requests"
}
else {
    # Use AzureDiagnostics table query
    $query = "AzureDiagnostics
| where Category == 'ApplicationGatewayAccessLog' and 
        OperationName == 'ApplicationGatewayAccess' and
        TimeGenerated >= ago($($Minutes)min)
| summarize count() by clientIP_s
| project IP=clientIP_s, Requests=count_
| where Requests > $RequestLimit
| order by Requests"
}

$query
$workspace = Get-AzOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName

$queryResult = Invoke-AzOperationalInsightsQuery -Workspace $workspace -Query $query
$queryResult.Results | Format-Table

# Example:
# --------
# IP           Requests
# --           --------
# 1.2.3.4      122
# 3.4.5.6      10

$IPs = $queryResult.Results | ForEach-Object { $_.IP }
$IPs

if (0 -eq $IPs.Count) {
    "No IPs found with given query conditions. Removing rule."
}
else {
    $variable = New-AzApplicationGatewayFirewallMatchVariable -VariableName RemoteAddr
    $condition = New-AzApplicationGatewayFirewallCondition -MatchVariable $variable -Operator IPMatch -MatchValue $IPs
    $rule = New-AzApplicationGatewayFirewallCustomRule -Name BlockSpecificIPs -Priority $RulePriority -RuleType MatchRule -MatchCondition $condition -Action Block
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
