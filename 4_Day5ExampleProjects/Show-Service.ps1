function Show-ServiceStatus {
    [CmdletBinding()]
    param ()

    # Get all services
    $services = Get-Service | Sort-Object Status, DisplayName

    foreach ($service in $services) {
        if ($service.Status -eq 'Running') {
            Write-Host "$($service.DisplayName) [$($service.Status)]" -ForegroundColor Green
        } elseif ($service.Status -eq 'Stopped') {
            Write-Host "$($service.DisplayName) [$($service.Status)]" -ForegroundColor Red
        } else {
            Write-Host "$($service.DisplayName) [$($service.Status)]" -ForegroundColor Yellow
        }
    }
}

Show-ServiceStatus