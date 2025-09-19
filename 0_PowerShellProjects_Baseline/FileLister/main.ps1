param(
    [string]$Path = ".",
    [switch]$Recurse
)

if (-not (Test-Path $Path)) {
    Write-Error "Path '$Path' does not exist."
    exit 1
}

Get-ChildItem -Path $Path -File -Recurse:$Recurse | ForEach-Object {
    Write-Host $_.FullName
}
