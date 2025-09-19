# input_handler.ps1
# Functions to load images and datasets for the PowerShell CNN 2D project

# Note: Native PowerShell has limited image processing capabilities. This file provides
# simple text/CSV readers and a lightweight image reader using .NET System.Drawing if available.

function Read-CsvToMatrix {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [char]$Delimiter = ','
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    $lines = Get-Content -Path $Path | Where-Object { $_ -ne '' }
    $matrix = @()
    foreach ($line in $lines) {
        $parts = $line -split $Delimiter
        $row = @()
        foreach ($p in $parts) { $row += [double]::Parse($p) }
        $matrix += ,$row
    }
    return $matrix
}

function Read-TxtToMatrix {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [string]$RowDelimiter = '\n',
        [string]$ColDelimiter = ' '
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    $text = Get-Content -Path $Path -Raw
    $lines = $text -split "\r?\n" | Where-Object { $_ -ne '' }
    $matrix = @()
    foreach ($line in $lines) {
        $parts = $line -split $ColDelimiter | Where-Object { $_ -ne '' }
        $row = @()
        foreach ($p in $parts) { $row += [double]::Parse($p) }
        $matrix += ,$row
    }
    return $matrix
}

function Read-ImageToMatrix {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$Grayscale
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    try {
        Add-Type -AssemblyName System.Drawing
    } catch {
        throw "System.Drawing is not available in this environment. Cannot load images."
    }
    $bmp = [System.Drawing.Bitmap]::FromFile($Path)
    $rows = $bmp.Height
    $cols = $bmp.Width
    $matrix = New-Object 'object[]' $rows
    try {
        $rect = New-Object System.Drawing.Rectangle(0,0,$cols,$rows)
        $bmpData = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, $bmp.PixelFormat)
        $bytesPerPixel = [System.Drawing.Image]::GetPixelFormatSize($bmp.PixelFormat) / 8
        $stride = $bmpData.Stride
        $bufferSize = [math]::Abs($stride) * $rows
        $buffer = New-Object byte[] $bufferSize
        [System.Runtime.InteropServices.Marshal]::Copy($bmpData.Scan0, $buffer, 0, $bufferSize)
        for ($y = 0; $y -lt $rows; $y++) {
            $rowArr = New-Object 'double[]' $cols
            for ($x = 0; $x -lt $cols; $x++) {
                $idx = $y * $stride + $x * $bytesPerPixel
                $b = $buffer[$idx]
                $g = $buffer[$idx + 1]
                $r = $buffer[$idx + 2]
                if ($Grayscale) {
                    $gray = ($r * 0.299 + $g * 0.587 + $b * 0.114)
                    $rowArr[$x] = $gray
                } else {
                    $rowArr[$x] = (($r + $g + $b) / 3)
                }
            }
            $matrix[$y] = $rowArr
        }
        $bmp.UnlockBits($bmpData)
    } catch {
        # fallback to slower GetPixel
        for ($y = 0; $y -lt $rows; $y++) {
            $rowArr = New-Object 'double[]' $cols
            for ($x = 0; $x -lt $cols; $x++) {
                $c = $bmp.GetPixel($x,$y)
                if ($Grayscale) { $rowArr[$x] = ($c.R * 0.299 + $c.G * 0.587 + $c.B * 0.114) } else { $rowArr[$x] = (($c.R + $c.G + $c.B) / 3) }
            }
            $matrix[$y] = $rowArr
        }
    } finally {
        $bmp.Dispose()
    }
    return ,$matrix
}

function Load-Dataset {
    param(
        [Parameter(Mandatory)]
        [string]$Dir,
        [ValidateSet('csv','txt','images')]
        [string]$Type = 'csv',
        [switch]$Grayscale
    )
    if (-not (Test-Path $Dir)) { throw "Directory not found: $Dir" }
    $dataset = @()
    if ($Type -eq 'csv') {
        Get-ChildItem -Path $Dir -Filter '*.csv' | ForEach-Object {
            $matrix = Read-CsvToMatrix -Path $_.FullName
            $dataset += [PSCustomObject]@{Path=$_.FullName; Matrix=$matrix}
        }
    } elseif ($Type -eq 'txt') {
        Get-ChildItem -Path $Dir -Filter '*.txt' | ForEach-Object {
            $matrix = Read-TxtToMatrix -Path $_.FullName
            $dataset += [PSCustomObject]@{Path=$_.FullName; Matrix=$matrix}
        }
    } else {
        Get-ChildItem -Path $Dir -Include *.png,*.jpg,*.jpeg -File | ForEach-Object {
            $matrix = Read-ImageToMatrix -Path $_.FullName -Grayscale:$Grayscale
            $dataset += [PSCustomObject]@{Path=$_.FullName; Matrix=$matrix}
        }
    }
    return $dataset
}

# Read the project's funny.csv which contains text lines ending with TRUE/FALSE (possibly with a dot separator)
function Read-FunnyCsv {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    $lines = Get-Content -Path $Path | Where-Object { $_ -ne '' }
    $results = @()
    foreach ($line in $lines) {
        # Extract trailing TRUE/FALSE (case-insensitive), allow optional non-word separator like '.'
        if ($line -match "(?i)\b(TRUE|FALSE)\s*$") {
            $labelStr = $matches[1].ToUpper()
            # remove the trailing label and any whitespace/punctuation before it
            $text = ($line -replace "(?i)(TRUE|FALSE)\s*$", '').Trim()
        } else {
            # fallback: keep the whole line as text and default label to FALSE
            $labelStr = 'FALSE'
            $text = $line.Trim()
        }
        $label = if ($labelStr -eq 'TRUE') { 1 } else { 0 }
        $results += [PSCustomObject]@{Text=$text; Label=$label}
    }
    return $results
}

# Convert text to a fixed-size character grid (default 28x28). Each cell contains a normalized char code (0..1).
function Convert-TextToCharGrid {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,
        [int]$Size = 28
    )
    # If empty, return zero grid
    if ([string]::IsNullOrWhiteSpace($Text)) {
        $grid = New-Object 'object[]' $Size
        for ($i = 0; $i -lt $Size; $i++) { $grid[$i] = (New-Object 'double[]' $Size) }
        return ,$grid
    }
    # Normalize whitespace and lowercase
    $s = $Text.ToLower() -replace '\s+', ' '
    $chars = $s.ToCharArray()
    $grid = New-Object 'object[]' $Size
    $total = $Size * $Size
    for ($i = 0; $i -lt $Size; $i++) {
        $row = New-Object 'double[]' $Size
        for ($j = 0; $j -lt $Size; $j++) { $row[$j] = 0.0 }
        $grid[$i] = $row
    }
    for ($k = 0; $k -lt [math]::Min($chars.Length, $total); $k++) {
        $r = [math]::Floor($k / $Size)
        $c = $k % $Size
        $code = [int]$chars[$k]
        # map to 0..1 using 0..127 ASCII range
        $val = [math]::Max(0, [math]::Min(127, $code)) / 127.0
        $grid[$r][$c] = $val
    }
    return ,$grid
}

# Read an OpenDocument Spreadsheet (.ods) and return the first sheet as a matrix (array of rows)
function Read-OdsToMatrix {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [switch]$ConvertNumbers
    )
    if (-not (Test-Path $Path)) { throw "File not found: $Path" }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    } catch {
        # if Add-Type fails, proceed; ZipFile may still be available
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        throw "Unable to open ODS file as zip archive: $_"
    }
    $entry = $zip.Entries | Where-Object { $_.FullName -ieq 'content.xml' } | Select-Object -First 1
    if (-not $entry) { $zip.Dispose(); throw "content.xml not found inside ODS file" }
    $sr = $entry.Open()
    $reader = New-Object System.IO.StreamReader($sr)
    $xmlString = $reader.ReadToEnd()
    $reader.Close(); $sr.Close(); $zip.Dispose()

    [xml]$doc = $xmlString
    # Find table elements (ignore namespace prefixes using local-name())
    $tables = $doc.SelectNodes("//*[local-name() = 'table']")
    if ($tables.Count -eq 0) { throw "No table found in ODS content.xml" }
    # Default: parse first table
    $table = $tables[0]
    $rows = $table.SelectNodes("*[local-name() = 'table-row']")
    $matrix = @()
    foreach ($r in $rows) {
        $cells = $r.SelectNodes("*[local-name() = 'table-cell']")
        $rowArr = @()
        foreach ($c in $cells) {
            # handle repeated columns
            $repAttr = $null
            foreach ($a in $c.Attributes) { if ($a.LocalName -eq 'number-columns-repeated') { $repAttr = $a.Value } }
            $rep = 1
            if ($repAttr) { [int]$rep = [int]$repAttr }
            # extract text from text:p elements inside the cell
            $ps = $c.SelectNodes(".//*[local-name() = 'p']")
            $text = ''
            if ($ps -ne $null -and $ps.Count -gt 0) {
                $parts = @()
                foreach ($p in $ps) { $parts += $p.InnerText }
                $text = ($parts -join " `n").Trim()
            } else {
                # sometimes the cell text is in the cell's value attribute
                $valAttr = $null
                foreach ($a in $c.Attributes) { if ($a.LocalName -eq 'value') { $valAttr = $a.Value } }
                if ($valAttr) { $text = $valAttr } else { $text = '' }
            }
            # optionally convert numeric-like strings
            $cellVal = $text
            if ($ConvertNumbers -and ($cellVal -match '^[+-]?([0-9]*[.])?[0-9]+$')) {
                try { $cellVal = [double]$cellVal } catch { }
            }
            for ($k = 0; $k -lt $rep; $k++) { $rowArr += $cellVal }
        }
        $matrix += ,$rowArr
    }
    return $matrix
}

if ($PSModuleInfo) { Export-ModuleMember -Function Read-CsvToMatrix,Read-TxtToMatrix,Read-ImageToMatrix,Load-Dataset,Read-FunnyCsv,Convert-TextToCharGrid,Read-OdsToMatrix }
