# main.ps1
# Entry point for 2D Convolutional Neural Network in PowerShell
. "$PSScriptRoot\cnn2d.ps1"
. "$PSScriptRoot\nnlib.ps1"
. "$PSScriptRoot\input_handler.ps1"
. "$PSScriptRoot\data_processing.ps1"
. "$PSScriptRoot\model_metrics.ps1"
. "$PSScriptRoot\matplotlib_ps.ps1"

Write-Host "Running end-to-end pipeline using funny.ods (fallback to funny.csv)"

$odsPath = Join-Path $PSScriptRoot 'funny.ods'
$csvPath = Join-Path $PSScriptRoot 'funny.csv'
$rows = @()
if (Test-Path $odsPath) {
    Write-Host "Found funny.ods - reading..."
    $mat = Read-OdsToMatrix -Path $odsPath
    # Interpret first column as original feature, second column as label
    $origFeaturesAll = @()
    foreach ($r in $mat) {
        if ($r.Count -ge 2) {
            $origFeaturesAll += $r[0].ToString().Trim()
            $labRaw = $r[1]
        } elseif ($r.Count -eq 1) {
            $origFeaturesAll += $r[0].ToString().Trim()
            $labRaw = ''
        } else {
            continue
        }
        $label = 0
        if ($labRaw -match '(?i)^(true|1)$') { $label = 1 } elseif ($labRaw -match '(?i)^(false|0)$') { $label = 0 } else { $label = 0 }
        $rows += [PSCustomObject]@{Text=$origFeaturesAll[-1]; Label=$label}
    }
    Write-Host "Original features (first column) sample list:" -ForegroundColor Cyan
    $origFeaturesAll | ForEach-Object { Write-Host " - $_" }
} elseif (Test-Path $csvPath) {
    Write-Host "funny.ods not found - reading funny.csv instead"
    $rows = Read-FunnyCsv -Path $csvPath
} else {
    throw "No dataset found (neither funny.ods nor funny.csv present)"
}

Write-Host "Loaded $($rows.Count) samples. Using SampleSize=10 and TestSize=0.2"

# Use only 10 samples (deterministic by Seed)
$sampleSize = 10
$seed = 42
$rand = New-Object System.Random($seed)
$indices = 0..($rows.Count - 1) | Sort-Object { $rand.Next() }
$indices = $indices[0..([math]::Min($sampleSize-1, $indices.Count-1))]
$sel = $indices | ForEach-Object { $rows[$_] }

# Convert texts to 28x28 grids and normalize
$X = @(); $y = @()
foreach ($item in $sel) {
    $grid = Convert-TextToCharGrid -Text $item.Text -Size 28
    # Convert grid to double[][] explicitly
    $grid2 = New-Object 'object[]' $grid.Count
    for ($i=0;$i -lt $grid.Count;$i++) { $grid2[$i] = [double[]]$grid[$i] }
    $norm = Normalize-Image -Image $grid2 -Method 'minmax'
    $X += ,$norm
    $y += [int]$item.Label
}

# Sanitize grids: ensure each sample is a 28x28 double[] array
for ($idx=0;$idx -lt $X.Count;$idx++) {
    $img = $X[$idx]
    if ($null -eq $img -or -not ($img -is [System.Array]) -or $img.Count -ne 28) {
        Write-Host "Warning: sample $idx has invalid grid; replacing with zero 28x28" -ForegroundColor Yellow
        $zero = New-Object 'object[]' 28
        for ($r=0;$r -lt 28;$r++) { $row = New-Object 'double[]' 28; for ($c=0;$c -lt 28;$c++) { $row[$c]=0.0 }; $zero[$r] = $row }
        $X[$idx] = $zero
        continue
    }
    for ($r=0;$r -lt $img.Count;$r++) {
        if (-not ($img[$r] -is [double[]]) -or $img[$r].Count -ne 28) {
            Write-Host "Fixing row $r of sample $idx to double[28]" -ForegroundColor Yellow
            $row = New-Object 'double[]' 28
            $len = 0
            try { $len = $img[$r].Count } catch { $len = 0 }
            for ($c=0;$c -lt [math]::Min(28,$len);$c++) { $row[$c] = [double]$img[$r][$c] }
            for ($c=$len;$c -lt 28;$c++) { $row[$c] = 0.0 }
            $img[$r] = $row
        }
    }
    $X[$idx] = $img
}

# Diagnostics: ensure no image has zero rows or zero columns
for ($idx=0;$idx -lt $X.Count;$idx++) {
    $img = $X[$idx]
    $rows = 0; $cols = 0
    try { $rows = $img.Count } catch { $rows = 0 }
    try { $cols = $img[0].Count } catch { $cols = 0 }
    Write-Host "Sample $idx dimensions: $rows x $cols"
    if ($rows -eq 0 -or $cols -eq 0) {
        Write-Host "Replacing sample $idx with zero 28x28 due to invalid dimensions" -ForegroundColor Yellow
        $zero = New-Object 'object[]' 28
        for ($r=0;$r -lt 28;$r++) { $row = New-Object 'double[]' 28; for ($c=0;$c -lt 28;$c++) { $row[$c]=0.0 }; $zero[$r] = $row }
        $X[$idx] = $zero
    }
}

# Split train/test: TestSize 0.2
$split = Split-TrainTest -X $X -y $y -TestSize 0.2 -Seed $seed
Write-Host "Train samples: $($split.X_train.Count), Test samples: $($split.X_test.Count)"

# Local lightweight implementations to avoid binding issues with module functions
function Local-Convolution2D {
    param([object[]]$Input, [object[]]$Kernel)
    if ($null -eq $Input -or $Input.Count -eq 0) { return ,(New-Object 'object[]' 0) }
    $inR = $Input.Count; $inC = $Input[0].Count
    $kR = $Kernel.Count; $kC = $Kernel[0].Count
    $oR = $inR - $kR + 1; $oC = $inC - $kC + 1
    if ($oR -le 0 -or $oC -le 0) { return ,(New-Object 'object[]' 0) }
    $out = New-Object 'object[]' $oR
    for ($i=0;$i -lt $oR;$i++) {
        $row = New-Object 'double[]' $oC
        for ($j=0;$j -lt $oC;$j++) {
            $sum = 0.0
            for ($m=0;$m -lt $kR;$m++) {
                $inRow = $Input[$i+$m]
                $kRow = $Kernel[$m]
                for ($n=0;$n -lt $kC;$n++) { $sum += [double]$inRow[$j+$n] * [double]$kRow[$n] }
            }
            $row[$j] = $sum
        }
        $out[$i] = $row
    }
    return ,$out
}

function Local-ReLU { param([object[]]$Input) $out = New-Object 'object[]' $Input.Count; for ($i=0;$i -lt $Input.Count;$i++){ $r = $Input[$i]; $nr = New-Object 'double[]' $r.Count; for ($j=0;$j -lt $r.Count;$j++){ $nr[$j] = [math]::Max(0,[double]$r[$j]) }; $out[$i] = $nr }; return ,$out }

function Local-Pooling { param([object[]]$Input, [int]$PoolSize=2) $rows=$Input.Count; $cols=$Input[0].Count; $oR=[math]::Floor($rows/$PoolSize); $oC=[math]::Floor($cols/$PoolSize); if ($oR -le 0 -or $oC -le 0) { return ,(New-Object 'object[]' 0) }; $out=New-Object 'object[]' $oR; for ($i=0;$i -lt $oR;$i++){ $row=New-Object 'double[]' $oC; for($j=0;$j -lt $oC;$j++){ $max=-1e308; for($m=0;$m -lt $PoolSize;$m++){ $inRow=$Input[$i*$PoolSize+$m]; for($n=0;$n -lt $PoolSize;$n++){ $v=[double]$inRow[$j*$PoolSize+$n]; if ($v -gt $max){ $max=$v } } } $row[$j]=$max } $out[$i]=$row } return ,$out }

function Local-Flatten { param([object[]]$Input) $flat = New-Object 'System.Collections.Generic.List[double]'; foreach($r in $Input){ for($i=0;$i -lt $r.Count;$i++){ $flat.Add([double]$r[$i]) } }; return ,([double[]]$flat.ToArray()) }

# Feature extraction: small conv -> relu -> pool -> flatten (produce 196-length vector)
function Extract-FeaturesLocal {
    param([object[]]$grid)
    # Defensive checks: ensure grid is an array of rows and has content
    if ($null -eq $grid -or -not ($grid -is [System.Array]) -or $grid.Count -eq 0) {
        # return zero vector length 196
        $z = New-Object 'double[]' 196
        for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }
        return ,$z
    }
    $convKernel = @( @(0.2, -0.1), @(0.1, 0.05) )
    # Ensure rows are arrays of doubles
    $prepared = New-Object 'object[]' $grid.Count
    for ($ri=0;$ri -lt $grid.Count;$ri++) { $prepared[$ri] = [double[]]$grid[$ri] }
    $conv = Local-Convolution2D -Input $prepared -Kernel $convKernel
    if ($null -eq $conv -or ($conv -is [System.Array] -and $conv.Count -eq 0)) {
        $z = New-Object 'double[]' 196
        for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }
        return ,$z
    }
    $act = Local-ReLU -Input $conv
    $pool = Local-Pooling -Input $act -PoolSize 2
    if ($null -eq $pool -or $pool.Count -eq 0) {
        $z = New-Object 'double[]' 196
        for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }
        return ,$z
    }
    $flat = Local-Flatten -Input $pool
    # pad or truncate to 196
    for ($k = $flat.Count; $k -lt 196; $k++) { $flat += 0 }
    if ($flat.Count -gt 196) { $flat = $flat[0..195] }
    return ,([double[]]$flat)
}

Write-Host "Extracting features..."
$trainFeatures = @(); $testFeatures = @()
for ($i=0;$i -lt $split.X_train.Count;$i++) { $trainFeatures += ,(Extract-FeaturesLocal -grid $split.X_train[$i]) }
for ($i=0;$i -lt $split.X_test.Count;$i++) { $testFeatures += ,(Extract-FeaturesLocal -grid $split.X_test[$i]) }


# Feature selection: use ANOVA to pick top K features
$k = 50
try {
    $indicesSelected = Select-ByANOVA -X $trainFeatures -y $split.y_train -k $k
} catch {
    # fallback: take first k
    $indicesSelected = 0..([math]::Min($k-1,195))
}
Write-Host "Selected $($indicesSelected.Count) features (top $k)"

# Reduce feature vectors to selected indices
function Reduce-Features { param($vec,$idx) $out = New-Object 'double[]' $idx.Count; for ($i=0;$i -lt $idx.Count;$i++) { $out[$i] = [double]$vec[$idx[$i]] }; return $out }

$trainReduced = @(); $testReduced = @()
foreach ($v in $trainFeatures) { $trainReduced += ,(Reduce-Features -vec $v -idx $indicesSelected) }
foreach ($v in $testFeatures) { $testReduced += ,(Reduce-Features -vec $v -idx $indicesSelected) }

# PCA expansion: compute PCA on reduced training features and append top-k components
$pcaK = 10
if ($trainReduced.Count -gt 0) {
    $availableDim = $trainReduced[0].Count
    $kUse = [math]::Min($pcaK, $availableDim)
    Write-Host "Computing PCA on reduced training features (k=$kUse)..."
    try {
        $pcaModel = Compute-PCA -X $trainReduced -k $kUse -Seed $seed
    } catch {
        Write-Warning "Compute-PCA failed: $_"
        $pcaModel = $null
    }
    if ($null -ne $pcaModel) {
        $trainPcaProj = @(); foreach ($r in $trainReduced) { $trainPcaProj += ,(Project-PCA -Vector $r -Components $pcaModel.Components -Mean $pcaModel.Mean) }
        $testPcaProj = @(); foreach ($r in $testReduced) { $testPcaProj += ,(Project-PCA -Vector $r -Components $pcaModel.Components -Mean $pcaModel.Mean) }

        $trainExpanded = @()
        for ($i=0; $i -lt $trainReduced.Count; $i++) {
            $orig = $trainReduced[$i]; $pc = $trainPcaProj[$i]
            $newLen = $orig.Count + $pc.Count
            $newArr = New-Object 'double[]' $newLen
            for ($j=0;$j -lt $orig.Count;$j++){ $newArr[$j] = [double]$orig[$j] }
            for ($j=0;$j -lt $pc.Count;$j++){ $newArr[$orig.Count + $j] = [double]$pc[$j] }
            $trainExpanded += ,$newArr
        }

        $testExpanded = @()
        for ($i=0; $i -lt $testReduced.Count; $i++) {
            $orig = $testReduced[$i]; $pc = $testPcaProj[$i]
            $newLen = $orig.Count + $pc.Count
            $newArr = New-Object 'double[]' $newLen
            for ($j=0;$j -lt $orig.Count;$j++){ $newArr[$j] = [double]$orig[$j] }
            for ($j=0;$j -lt $pc.Count;$j++){ $newArr[$orig.Count + $j] = [double]$pc[$j] }
            $testExpanded += ,$newArr
        }

        $trainReduced = $trainExpanded
        $testReduced = $testExpanded
        Write-Host "Appended $kUse PCA components; new feature dim: $($trainReduced[0].Count)"
    } else {
        Write-Warning "PCA model null - skipping PCA expansion"
    }
}

# Train a logistic regression on reduced (and PCA-expanded) features
if ($trainReduced.Count -gt 0) { $nFeat = $trainReduced[0].Count } else { $nFeat = $indicesSelected.Count }
$rng = New-Object System.Random 123
$weights = New-Object 'double[]' $nFeat
for ($i=0;$i -lt $nFeat;$i++) { $weights[$i] = ($rng.NextDouble() * 2 - 1) }
$bias = ($rng.NextDouble() * 2 - 1)
$lr = 0.1
$epochs = 20
Write-Host "Training logistic regression for $epochs epochs (features: $nFeat)"
for ($e=0;$e -lt $epochs;$e++) {
    for ($s=0;$s -lt $trainReduced.Count;$s++) {
        $x = $trainReduced[$s]; $label = $split.y_train[$s]
        $dot = 0.0
        for ($j=0;$j -lt $nFeat;$j++) { $dot += $x[$j] * $weights[$j] }
        $dot += $bias
        $pred = 1 / (1 + [math]::Exp(-$dot))
        $err = $pred - $label
        for ($j=0;$j -lt $nFeat;$j++) { $weights[$j] = $weights[$j] - $lr * $err * $x[$j] }
        $bias = $bias - $lr * $err
    }
}

# Evaluate on test
$probs = @(); $yTrue = $split.y_test
for ($s=0;$s -lt $testReduced.Count;$s++) {
    $x = $testReduced[$s]
    $dot = 0.0
    for ($j=0;$j -lt $nFeat;$j++) { $dot += $x[$j] * $weights[$j] }
    $dot += $bias
    $p = 1 / (1 + [math]::Exp(-$dot))
    $probs += $p
}

# Convert to binary preds
$yPred = @()
foreach ($p in $probs) { $yPred += ([int]([math]::Round($p))) }

Write-Host "Computing F1 score..."
$f1 = Get-F1Score -Predicted $yPred -Actual $yTrue
Write-Host "F1 score on test set: $f1"