Set-Location -LiteralPath 'C:\Users\Student\Documents\Visual Studio Programs\3_PowerShellProject_CNN'
$ErrorActionPreference = 'Stop'
try {
    .\main.ps1
} catch {
    Write-Host '--- EXCEPTION ---'
    $_ | Format-List * -Force
    exit 1
}
