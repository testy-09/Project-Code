param([string]$OdsPath)
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not (Test-Path $OdsPath)) { Write-Error "File not found: $OdsPath"; exit 2 }
$tempFolder = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
[System.IO.Compression.ZipFile]::ExtractToDirectory($OdsPath,$tempFolder)
$contentFile = Join-Path $tempFolder 'content.xml'
if (-not (Test-Path $contentFile)) { Write-Error "content.xml not found inside ODS"; Remove-Item -Recurse -Force $tempFolder; exit 3 }
[xml]$xml = Get-Content -Path $contentFile -Raw
# Setup namespace manager
$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
# Register common ODF namespaces if present
$ns.AddNamespace('office', $xml.DocumentElement.GetNamespaceOfPrefix('office'))
$ns.AddNamespace('table', $xml.DocumentElement.GetNamespaceOfPrefix('table'))
$ns.AddNamespace('text', $xml.DocumentElement.GetNamespaceOfPrefix('text'))
$ns.AddNamespace('draw', $xml.DocumentElement.GetNamespaceOfPrefix('draw'))
# Select all table-row nodes
$rows = $xml.SelectNodes('//table:table-row', $ns)
$out = @()
foreach ($r in $rows) {
    # Find first cell, then any text:p children
    $cell = $r.SelectSingleNode('table:table-cell', $ns)
    if ($null -eq $cell) { $out += ''; continue }
    # Aggregate all text:p descendants
    $ps = $cell.SelectNodes('.//text:p', $ns)
    if ($ps -and $ps.Count -gt 0) {
        $parts = @(); foreach ($p in $ps) { $parts += $p.InnerText }
        $txt = ($parts -join ' ') -replace '\s+',' '
        $out += $txt.Trim()
    } else {
        # If no text:p, maybe direct text
        $txt = $cell.InnerText -replace '\s+',' '
        $out += $txt.Trim()
    }
}
# Save and clean up
$outFile = Join-Path (Split-Path $OdsPath) 'scripts\funny_firstcol_xml.txt'
try { Set-Content -Path $outFile -Value ($out -join "`n") -Encoding UTF8 } catch { Write-Warning "Failed to write output file: $_" }
Remove-Item -Recurse -Force $tempFolder
$out | ForEach-Object { Write-Output $_ }
