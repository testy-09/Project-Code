param([string]$OdsPath)
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not (Test-Path $OdsPath)) { Write-Error "File not found: $OdsPath"; exit 2 }
$tempFolder = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
[System.IO.Compression.ZipFile]::ExtractToDirectory($OdsPath,$tempFolder)
$contentFile = Join-Path $tempFolder 'content.xml'
if (-not (Test-Path $contentFile)) { Write-Error "content.xml not found inside ODS"; Remove-Item -Recurse -Force $tempFolder; exit 3 }
$content = Get-Content -Path $contentFile -Raw
$rowPattern = '<table:table-row.*?>.*?<\/table:table-row>'
$rows = [regex]::Matches($content,$rowPattern,[System.Text.RegularExpressions.RegexOptions]::Singleline)
$out = @()
$cellPattern = '<table:table-cell[^>]*>(?:<text:p[^>]*>)?(.*?)(?:<\/text:p>)?'
foreach ($r in $rows) {
    $cells = [regex]::Matches($r.Value,$cellPattern,'Singleline')
    if ($cells.Count -gt 0) {
        $first = $cells[0].Groups[1].Value -replace '\n',' ' -replace '\s+',' '
        $out += $first.Trim()
    }
}
# Save to a file for reliable reading
$outFile = Join-Path (Split-Path $OdsPath) 'scripts\funny_firstcol.txt'
try { Set-Content -Path $outFile -Value ($out -join "`n") -Encoding UTF8 } catch { Write-Warning "Failed to write output file: $_" }
Remove-Item -Recurse -Force $tempFolder
$out | ForEach-Object { Write-Output $_ }
