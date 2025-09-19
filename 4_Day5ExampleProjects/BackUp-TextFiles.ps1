# BackUp-TxtFiles.ps1
# Description: Backs up all .txt files from C:\Data to D:\Backup, preserving directory structure.

$source = "C:\Data"
$destination = "D:\Backup"

# Ensure destination directory exists
if (-not (Test-Path -Path $destination)) {
    New-Item -Path $destination -ItemType Directory -Force
}

# Get all .txt files recursively from source
$txtFiles = Get-ChildItem -Path $source -Recurse -Filter *.txt -File

foreach ($file in $txtFiles) {
    # Get relative path from source directory
    $relativePath = $file.FullName.Substring($source.Length).TrimStart('\')

    # Construct destination path
    $destFilePath = Join-Path -Path $destination -ChildPath $relativePath

    # Ensure destination subdirectory exists
    $destDir = Split-Path -Path $destFilePath -Parent
    if (-not (Test-Path -Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force
    }

    # Copy the file
    Copy-Item -Path $file.FullName -Destination $destFilePath -Force
}

Write-Host "Backup complete. $($txtFiles.Count) .txt files copied." -ForegroundColor Green
