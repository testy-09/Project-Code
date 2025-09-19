# Fetch-ApiData.ps1
# Connects to an API endpoint and saves the JSON response to a file

# === Configuration ===
$apiUrl = "https://api.example.com/endpoint"   # Replace with the actual API URL
$outputFile = "C:\Temp\api-response.json"      # Change path as needed
$apiKey = "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"

# === Prepare Headers ===
$headers = @{
    "Authorization" = "Bearer $apiKey"
    "Content-Type"  = "application/json"
}

# === Make API Request ===
try {
    Write-Host "Requesting data from API..." -ForegroundColor Cyan

    $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers

    # Convert the response to formatted JSON
    $json = $response | ConvertTo-Json -Depth 10

    # Ensure output directory exists
    $outputDir = Split-Path $outputFile
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    # Save JSON to file
    $json | Out-File -FilePath $outputFile -Encoding UTF8

    Write-Host "✅ JSON response saved to: $outputFile" -ForegroundColor Green
}
catch {
    Write-Error "❌ Error occurred: $_"
}