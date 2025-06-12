param(
    [Parameter(Mandatory = $true)]
    [string]$NavigateUri,

    [Parameter()]
    [string]$ReportUri = "", # E.g., https://<yourapp>.azurewebsites.net/api/serverstatistics

    [Parameter()]
    [int]$ReportInterval = 10, # Default to 10 seconds
    
    [Parameter()]
    [int]$InstanceCount = 1, # Default to 1 instance
        
    [Parameter()]
    [string]$GeographyGroup = "", # Optional geography group, e.g., "Europe", "North America"

    [Parameter()]
    [string]$Location = "", # Optional location, e.g., "eastus", "westeurope"

    [Parameter()]
    [int]$TestDuration = 60 # Default to 60 seconds
)

# Function to generate a unique container name
function Get-UniqueContainerName {
    return "perftest-$(Get-Date -Format 'yyyyMMddHHmmss')-$(Get-Random -Maximum 9999)"
}

try {
    Write-Host "Starting performance test deployment..." -ForegroundColor Green
    
    if ($Location) {
        Write-Host "Using specified location: $Location" -ForegroundColor Yellow
        $allRegions = [array]@(
            @{ Location = $Location; Providers = @("Microsoft.ContainerInstance"); GeographyGroup = $GeographyGroup }
        )
    }
    else {
        # Get all available Azure regions
        Write-Host "Fetching available Azure regions..." -ForegroundColor Yellow

        $allRegions = Get-AzLocation | Where-Object { $_.Providers -contains "Microsoft.ContainerInstance" }
        if ($GeographyGroup) {
            $allRegions = $allRegions | Where-Object { $_.GeographyGroup -eq $GeographyGroup }
            Write-Host "Filtered regions by geography group '$GeographyGroup'. Found $($allRegions.Count) regions." -ForegroundColor Yellow
        }
    }
    
    
    if ($allRegions.Count -eq 0) {
        throw "No Azure regions found that support Container Instances"
    }
    
    Write-Host "Found $($allRegions.Count) regions supporting Container Instances" -ForegroundColor Green
    
    $selectedRegions = @()
    for ($i = 0; $i -lt $InstanceCount; $i++) {
        $selectedRegions += $allRegions | Get-Random
    }
    
    Write-Host "Selected region for instances: $($selectedRegions.Location -join ', ')" -ForegroundColor Cyan
    
    # Create resource group if needed
    $resourceGroupName = "rg-perftest-$(Get-Date -Format 'yyyyMMddHHmmss')"
    Write-Host "Creating resource group: $resourceGroupName" -ForegroundColor Yellow
    New-AzResourceGroup -Name $resourceGroupName -Location $selectedRegions[0].Location -Force
    
    # Deploy ACIs to selected regions using jobs
    $deploymentJobs = @()
    $deployedContainers = @()
    
    Write-Host "`nStarting parallel deployment of $($selectedRegions.Count) containers..." -ForegroundColor Yellow
    
    foreach ($region in $selectedRegions) {
        $containerName = Get-UniqueContainerName
        
        # Start deployment job
        $job = Start-Job -ScriptBlock {
            param($resourceGroupName, $containerName, $location, $navigateUri, $reportUri, $reportInterval)

            try {
                $envVars = @(
                    New-AzContainerInstanceEnvironmentVariableObject -Name "NavigateUri" -Value $navigateUri
                    New-AzContainerInstanceEnvironmentVariableObject -Name "ReportUri" -Value $reportUri
                    New-AzContainerInstanceEnvironmentVariableObject -Name "ReportInterval" -Value $reportInterval
                    New-AzContainerInstanceEnvironmentVariableObject -Name "ReportLocation" -Value $location
                )
                $container = New-AzContainerInstanceObject `
                    -Name navigator -Image "jannemattila.azurecr.io/web-navigator" `
                    -RequestCpu 1 `
                    -RequestMemoryInGb 1 `
                    -EnvironmentVariable $envVars
                New-AzContainerGroup `
                    -ResourceGroupName $resourceGroupName `
                    -Name $containerName `
                    -Location $location `
                    -Container $container `
                    -OsType Linux `
                    -RestartPolicy OnFailure `
                    -ErrorAction Stop
                
                return @{
                    Success = $true
                    Name = $containerName
                    Region = $location
                    ResourceGroup = $resourceGroupName
                    Error = $null
                }
            }
            catch {
                return @{
                    Success = $false
                    Name = $containerName
                    Region = $location
                    ResourceGroup = $resourceGroupName
                    Error = $_.Exception.Message
                }
            }
        } -ArgumentList $resourceGroupName, $containerName, $region.Location, $NavigateUri, $ReportUri, $ReportInterval

        $deploymentJobs += @{
            Job = $job
            ContainerName = $containerName
            Region = $region.Location
        }
        
        Write-Host "  - Started deployment job for container '$containerName' in region '$($region.Location)'" -ForegroundColor Gray
    }
    
    # Wait for all jobs to complete
    Write-Host "`nWaiting for all deployments to complete..." -ForegroundColor Yellow
    $completed = 0
    $startTime = Get-Date
    
    while ($completed -lt $deploymentJobs.Count) {
        $completedJobs = $deploymentJobs | Where-Object { $_.Job.State -eq 'Completed' -or $_.Job.State -eq 'Failed' }
        $completed = $completedJobs.Count
        
        $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
        $percentage = ($completed / $deploymentJobs.Count) * 100
        Write-Progress -Activity "Deploying containers" `
            -Status "$completed of $($deploymentJobs.Count) deployments completed (Running for $elapsed seconds)" `
            -PercentComplete $percentage
        
        Start-Sleep -Milliseconds 500
    }
    
    Write-Progress -Activity "Deploying containers" -Completed
    
    # Collect results from jobs
    Write-Host "`nDeployment results:" -ForegroundColor Yellow
    foreach ($jobInfo in $deploymentJobs) {
        $result = Receive-Job -Job $jobInfo.Job -Wait
        Remove-Job -Job $jobInfo.Job
        
        if ($result.Success) {
            $deployedContainers += @{
                Name = $result.Name
                Region = $result.Region
                ResourceGroup = $result.ResourceGroup
            }
            Write-Host "  ✓ Successfully deployed '$($result.Name)' to $($result.Region)" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ Failed to deploy '$($result.Name)' to $($result.Region): $($result.Error)" -ForegroundColor Red
        }
    }
    
    $deploymentEndTime = Get-Date
    $deploymentDuration = [int]($deploymentEndTime - $startTime).TotalSeconds
    Write-Host "`nDeployment completed in $deploymentDuration seconds" -ForegroundColor Cyan
    Write-Host "Deployed $($deployedContainers.Count) containers successfully" -ForegroundColor Green
    
    if ($deployedContainers.Count -eq 0) {
        throw "No containers were successfully deployed"
    }
    
    Write-Host "`nStarting performance test for $TestDuration seconds..." -ForegroundColor Cyan
    $endTime = (Get-Date).AddSeconds($TestDuration)
    while ((Get-Date) -lt $endTime) {
        $remaining = [int]($endTime - (Get-Date)).TotalSeconds
        Write-Progress -Activity "Running performance test" -Status "$remaining seconds remaining" -PercentComplete ((($TestDuration - $remaining) / $TestDuration) * 100)
        Start-Sleep -Seconds 1
    }
    
    Write-Progress -Activity "Running performance test" -Completed
    Write-Host "`nTest duration completed. Cleaning up resources..." -ForegroundColor Yellow
}
finally {
    Write-Host "Removing resource group '$resourceGroupName'..." -ForegroundColor Yellow
    try {
        Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob | Out-Null
        Write-Host "Resource group removal initiated (running as background job)" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to remove resource group: $_"
    }
    
    Write-Host "`nPerformance test completed and cleanup initiated!" -ForegroundColor Green
}