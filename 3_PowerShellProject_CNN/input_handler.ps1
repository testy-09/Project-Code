# input_handler.ps1
# Helper functions to read datasets and convert text to image-like grids

function Read-OdsToMatrix {
	param([Parameter(Mandatory)][string]$Path)
	# Simple ODS reader: ODS is a zip archive containing content.xml. We'll try to extract cell text heuristically.
	if (-not (Test-Path $Path)) { throw "File not found: $Path" }
	try {
	Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
	$tmp = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
	New-Item -ItemType Directory -Path $tmp -Force | Out-Null
	# Copy ODS to temp path first to avoid "file in use" errors when other processes hold the original
	$tmpOds = Join-Path $tmp 'data.ods'
	Copy-Item -Path $Path -Destination $tmpOds -Force
	[System.IO.Compression.ZipFile]::ExtractToDirectory($tmpOds, $tmp)
		$contentXml = Join-Path $tmp 'content.xml'
		if (-not (Test-Path $contentXml)) { throw 'content.xml not found inside ODS' }
		$xml = [xml](Get-Content -Path $contentXml -Raw)
		$ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
		$ns.AddNamespace('table','urn:oasis:names:tc:opendocument:xmlns:table:1.0')
		$ns.AddNamespace('text','urn:oasis:names:tc:opendocument:xmlns:text:1.0')
		$mat = @()
		$tables = $xml.SelectNodes('//table:table', $ns)
		foreach ($t in $tables) {
			$rows = $t.SelectNodes('.//table:table-row', $ns)
			foreach ($r in $rows) {
				$cells = $r.SelectNodes('./table:table-cell', $ns)
				$rowvals = @()
				foreach ($c in $cells) {
					$p = $c.SelectSingleNode('.//text:p', $ns)
					if ($p -ne $null) { $rowvals += $p.InnerText } else { $rowvals += '' }
				}
				$mat += ,$rowvals
			}
		}
	Remove-Item -Recurse -Force -Path $tmp
		return $mat
	} catch {
		Write-Warning "Failed to parse ODS: $_. Falling back to CSV-style parse"
		# Try to parse the file as CSV/text lines into rows (array of arrays)
		try {
			$lines = Get-Content -Path $Path -ErrorAction Stop
			$mat = @()
			foreach ($ln in $lines) {
				$parts = $ln -split ','
				$mat += ,$parts
			}
			return $mat
		} catch {
			Write-Warning "Fallback parsing also failed: $_"
			return @()
		}
	}
}

function Read-FunnyCsv {
	param([Parameter(Mandatory)][string]$Path)
	if (-not (Test-Path $Path)) { throw "CSV not found: $Path" }
	$lines = Get-Content -Path $Path
	$out = @()
	foreach ($ln in $lines) {
		$parts = $ln -split ','
		if ($parts.Count -ge 2) { $out += [PSCustomObject]@{Text=$parts[0].Trim(); Label = ([int]($parts[1].Trim() -as [int] -ne $null) -or 0)} } else { $out += [PSCustomObject]@{Text=$ln.Trim(); Label=0} }
	}
	return $out
}

function Convert-TextToCharGrid {
	param(
		[string]$Text = '',
		[int]$Size = 28
	)
	# Very small heuristic: render characters into a size x size grid by mapping char codes
	# This does not use graphics; instead we create a deterministic matrix from characters
	$grid = New-Object 'object[]' $Size
	if ($null -eq $Text -or $Text -eq '') {
		# return zero grid
		$grid = New-Object 'object[]' $Size
		for ($r=0;$r -lt $Size;$r++) { $row = New-Object 'double[]' $Size; for ($c=0;$c -lt $Size;$c++) { $row[$c]=0.0 }; $grid[$r]=$row }
		return ,$grid
	}
	$chars = $Text.ToCharArray()
	for ($r=0;$r -lt $Size;$r++) {
		$row = New-Object 'double[]' $Size
		for ($c=0;$c -lt $Size;$c++) {
			$idx = ($r * $Size + $c) % $chars.Count
			if ($chars.Count -eq 0) { $row[$c] = 0.0 } else { $row[$c] = [double][int]$chars[$idx] % 256 / 255.0 }
		}
		$grid[$r] = $row
	}
	return ,$grid
}

if ($PSModuleInfo) { Export-ModuleMember -Function Read-OdsToMatrix,Read-FunnyCsv,Convert-TextToCharGrid }
