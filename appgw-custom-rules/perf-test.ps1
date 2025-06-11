param(
    [Parameter(Mandatory = $true)]
    [string]$NavigateUri,
    
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
    
    # Deploy ACIs to selected regions
    $deployedContainers = @()
    
    foreach ($region in $selectedRegions) {
        try {
            $containerName = Get-UniqueContainerName
            Write-Host "Deploying container '$containerName' to region '$($region.Location)'..." -ForegroundColor Yellow
            
            # Create container instance
            $envVars = @(
                New-AzContainerInstanceEnvironmentVariableObject -Name "NavigateUri" -Value $NavigateUri
            )
            $containerImage = New-AzContainerInstanceObject `
                -Name navigator -Image "jannemattila.azurecr.io/web-navigator" `
                -RequestCpu 1 `
                -RequestMemoryInGb 1 `
                -EnvironmentVariable $envVars
            $container = New-AzContainerGroup `
                -ResourceGroupName $resourceGroupName `
                -Name $containerName `
                -Location $region.Location `
                -Container $containerImage `
                -OsType Linux `
                -RestartPolicy OnFailure
            
            $deployedContainers += @{
                Name = $containerName
                Region = $region.Location
                ResourceGroup = $resourceGroupName
            }
            
            Write-Host "Successfully deployed container to $($region.Location)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to deploy to region $($region.Location): $_"
        }
    }
    
    Write-Host "`nDeployed $($deployedContainers.Count) containers successfully" -ForegroundColor Green
    Write-Host "Running test for $TestDuration seconds..." -ForegroundColor Cyan
    
    # Display container information
    Write-Host "`nDeployed containers:" -ForegroundColor Yellow
    foreach ($container in $deployedContainers) {
        Write-Host "  - $($container.Name) in $($container.Region)" -ForegroundColor White
    }
    
    # Wait for test duration
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
    # Remove resource group
    if ($resourceGroupName) {
        Write-Host "Removing resource group '$resourceGroupName'..." -ForegroundColor Yellow
        try {
            Remove-AzResourceGroup -Name $resourceGroupName -Force -AsJob | Out-Null
            Write-Host "Resource group removal initiated (running as background job)" -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to remove resource group: $_"
        }
    }
    
    Write-Host "`nPerformance test completed and cleanup initiated!" -ForegroundColor Green
}