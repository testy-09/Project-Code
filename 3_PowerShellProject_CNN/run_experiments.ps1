# run_experiments.ps1
# Lightweight experiment runner for the CNN-features + PCA pipeline
param()

. "$PSScriptRoot\cnn2d.ps1"
. "$PSScriptRoot\nnlib.ps1"
. "$PSScriptRoot\input_handler.ps1"
. "$PSScriptRoot\data_processing.ps1"
. "$PSScriptRoot\model_metrics.ps1"
. "$PSScriptRoot\matplotlib_ps.ps1"

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

function Extract-FeaturesLocal {
    param([object[]]$grid)
    if ($null -eq $grid -or -not ($grid -is [System.Array]) -or $grid.Count -eq 0) {
        $z = New-Object 'double[]' 196
        for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }
        return ,$z
    }
    $convKernel = @( @(0.2, -0.1), @(0.1, 0.05) )
    $prepared = New-Object 'object[]' $grid.Count
    for ($ri=0;$ri -lt $grid.Count;$ri++) { $prepared[$ri] = [double[]]$grid[$ri] }
    $conv = Local-Convolution2D -Input $prepared -Kernel $convKernel
    if ($null -eq $conv -or ($conv -is [System.Array] -and $conv.Count -eq 0)) { $z = New-Object 'double[]' 196; for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }; return ,$z }
    $act = Local-ReLU -Input $conv
    $pool = Local-Pooling -Input $act -PoolSize 2
    if ($null -eq $pool -or $pool.Count -eq 0) { $z = New-Object 'double[]' 196; for ($i=0;$i -lt 196;$i++) { $z[$i] = 0.0 }; return ,$z }
    $flat = Local-Flatten -Input $pool
    for ($k = $flat.Count; $k -lt 196; $k++) { $flat += 0 }
    if ($flat.Count -gt 196) { $flat = $flat[0..195] }
    return ,([double[]]$flat)
}

function Run-Experiment {
    param(
        [int]$SampleSize = 10,
        [double]$TestSize = 0.2,
        [int]$PCAK = 10,
        [switch]$UseSMOTE = $false,
        [double]$L2 = 0.01,
        [int]$Seed = 42
    )

    Write-Host "=== Running experiment: SampleSize=$SampleSize TestSize=$TestSize PCAK=$PCAK SMOTE=$UseSMOTE L2=$L2 Seed=$Seed ==="

    $odsPath = Join-Path $PSScriptRoot 'funny.ods'
    $csvPath = Join-Path $PSScriptRoot 'funny.csv'
    $rows = @()
    if (Test-Path $odsPath) {
        $mat = Read-OdsToMatrix -Path $odsPath
        foreach ($r in $mat) {
            if ($r.Count -ge 2) { $text = $r[0].ToString().Trim(); $labRaw = $r[1] } elseif ($r.Count -eq 1) { $text = $r[0].ToString().Trim(); $labRaw = '' } else { continue }
            $label = 0
            if ($labRaw -match '(?i)^(true|1)$') { $label = 1 } elseif ($labRaw -match '(?i)^(false|0)$') { $label = 0 } else { $label = 0 }
            $rows += [PSCustomObject]@{Text=$text; Label=$label}
        }
    } elseif (Test-Path $csvPath) {
        $rows = Read-FunnyCsv -Path $csvPath
    } else { throw 'No dataset' }

    # sample
    $seedLocal = $Seed
    $rand = New-Object System.Random($seedLocal)
    $indices = 0..($rows.Count - 1) | Sort-Object { $rand.Next() }
    if ($SampleSize -gt 0 -and $SampleSize -lt $indices.Count) { $indices = $indices[0..($SampleSize - 1)] }
    $sel = $indices | ForEach-Object { $rows[$_] }

    # convert to grids and normalize
    $X = @(); $y = @()
    foreach ($item in $sel) {
        $grid = Convert-TextToCharGrid -Text $item.Text -Size 28
        $grid2 = New-Object 'object[]' $grid.Count
        for ($i=0;$i -lt $grid.Count;$i++) { $grid2[$i] = [double[]]$grid[$i] }
        $norm = Normalize-Image -Image $grid2 -Method 'minmax'
        $X += ,$norm; $y += [int]$item.Label
    }

    # split
    $split = Split-TrainTest -X $X -y $y -TestSize $TestSize -Seed $seedLocal
    Write-Host "Train: $($split.X_train.Count) Test: $($split.X_test.Count)"

    # features
    $trainFeatures = @(); $testFeatures = @()
    for ($i=0;$i -lt $split.X_train.Count;$i++) { $trainFeatures += ,(Extract-FeaturesLocal -grid $split.X_train[$i]) }
    for ($i=0;$i -lt $split.X_test.Count;$i++) { $testFeatures += ,(Extract-FeaturesLocal -grid $split.X_test[$i]) }

    # selection
    $k = 50
    try { $indicesSelected = Select-ByANOVA -X $trainFeatures -y $split.y_train -k $k } catch { $indicesSelected = 0..([math]::Min($k-1,195)) }
    $trainReduced = @(); $testReduced = @()
    foreach ($v in $trainFeatures) { $trainReduced += ,(Reduce-Features -vec $v -idx $indicesSelected) }
    foreach ($v in $testFeatures) { $testReduced += ,(Reduce-Features -vec $v -idx $indicesSelected) }

    # PCA
    $kUse = [math]::Min($PCAK, $trainReduced[0].Count)
    $pcaModel = Compute-PCA -X $trainReduced -k $kUse -Seed $seedLocal
    $trainPca = @(); foreach ($r in $trainReduced) { $trainPca += ,(Project-PCA -Vector $r -Components $pcaModel.Components -Mean $pcaModel.Mean) }
    $testPca = @(); foreach ($r in $testReduced) { $testPca += ,(Project-PCA -Vector $r -Components $pcaModel.Components -Mean $pcaModel.Mean) }
    # append
    $trainExpanded=@(); for ($i=0;$i -lt $trainReduced.Count;$i++){ $orig=$trainReduced[$i]; $pc=$trainPca[$i]; $new=New-Object 'double[]' ($orig.Count+$pc.Count); for($j=0;$j -lt $orig.Count;$j++){ $new[$j]=$orig[$j] }; for($j=0;$j -lt $pc.Count;$j++){ $new[$orig.Count+$j]=$pc[$j] }; $trainExpanded += ,$new }
    $testExpanded=@(); for ($i=0;$i -lt $testReduced.Count;$i++){ $orig=$testReduced[$i]; $pc=$testPca[$i]; $new=New-Object 'double[]' ($orig.Count+$pc.Count); for($j=0;$j -lt $orig.Count;$j++){ $new[$j]=$orig[$j] }; for($j=0;$j -lt $pc.Count;$j++){ $new[$orig.Count+$j]=$pc[$j] }; $testExpanded += ,$new }
    $trainX = $trainExpanded; $trainY = $split.y_train; $testX = $testExpanded; $testY = $split.y_test

    # optional SMOTE
    if ($UseSMOTE) {
        try { $sm = Invoke-SMOTE -X $trainX -y $trainY -N 200 -Seed $seedLocal; $trainX = $sm.X; $trainY = $sm.y; Write-Host "After SMOTE train size: $($trainX.Count)" } catch { Write-Warning "SMOTE failed: $_" }
    }

    # logistic with L2
    $nFeat = $trainX[0].Count
    $rng = New-Object System.Random(123)
    $w = New-Object 'double[]' $nFeat; for($i=0;$i -lt $nFeat;$i++){ $w[$i]=($rng.NextDouble()*2-1) }
    $b = ($rng.NextDouble()*2-1); $lr = 0.05; $epochs = 50
    for ($e=0;$e -lt $epochs;$e++){
        for ($s=0;$s -lt $trainX.Count;$s++){
            $x = $trainX[$s]; $label = $trainY[$s]
            $dot=0.0; for($j=0;$j -lt $nFeat;$j++){ $dot += $x[$j]*$w[$j] }
            $dot += $b; $pred = 1/(1+[math]::Exp(-$dot)); $err = $pred - $label
            for($j=0;$j -lt $nFeat;$j++){ $w[$j] = $w[$j] - $lr*($err*$x[$j] + $L2*$w[$j]) }
            $b = $b - $lr*$err
        }
    }

    # eval
    $probs = @(); for($s=0;$s -lt $testX.Count;$s++){ $x=$testX[$s]; $dot=0.0; for($j=0;$j -lt $nFeat;$j++){ $dot+=$x[$j]*$w[$j] }; $dot+=$b; $probs += 1/(1+[math]::Exp(-$dot)) }
    $preds = $probs | ForEach-Object { [int]([math]::Round($_)) }
    $f1 = Get-F1Score -Predicted $preds -Actual $testY
    Write-Host "Result: SampleSize=$SampleSize TestSize=$TestSize SMOTE=$UseSMOTE PCAK=$PCAK L2=$L2 -> F1=$f1"

    return [PSCustomObject]@{SampleSize=$SampleSize; TestSize=$TestSize; SMOTE=$UseSMOTE; PCAK=$PCAK; L2=$L2; F1=$f1; Preds=$preds; Actual=$testY }
}

# helper used by selection earlier (exists in main); re-use Reduce-Features if available, otherwise provide
if (-not (Get-Command -Name Reduce-Features -ErrorAction SilentlyContinue)) {
    function Reduce-Features { param($vec,$idx) $out = New-Object 'double[]' $idx.Count; for ($i=0;$i -lt $idx.Count;$i++) { $out[$i] = [double]$vec[$idx[$i]] }; return $out }
}

# Run two experiments: small(10) and larger(50)
$results = @()
$results += Run-Experiment -SampleSize 10 -TestSize 0.2 -PCAK 10 -UseSMOTE:$false -L2 0.01 -Seed 42
$results += Run-Experiment -SampleSize 50 -TestSize 0.2 -PCAK 10 -UseSMOTE:$true -L2 0.01 -Seed 42

Write-Host "\nSummary of runs:"
foreach ($r in $results) { Write-Host "$($r.SampleSize) samples SMOTE=$($r.SMOTE) -> F1=$($r.F1)" }

# End
