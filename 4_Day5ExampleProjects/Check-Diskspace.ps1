function Check-DiskSpace {
    [CmdletBinding()]
    param ()

    $thresholdPercent = 10

    # Get all local fixed drives
    $drives = Get-PSDrive -PSProvider 'FileSystem' | Where-Object { $_.Free -ne $null }

    foreach ($drive in $drives) {
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $totalGB = [math]::Round($drive.Used + $drive.Free / 1GB, 2)
        $percentFree = ($drive.Free / ($drive.Used + $drive.Free)) * 100

        $percentFreeRounded = [math]::Round($percentFree, 2)

        $message = "Drive $($drive.Name): $freeGB GB free ($percentFreeRounded% free)"

        if ($percentFree -lt $thresholdPercent) {
            Write-Host "[WARNING] $message" -ForegroundColor Red
        } else {
            Write-Host "$message" -ForegroundColor Green
        }
    }
}
