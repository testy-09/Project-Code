# Calculate correlation matrix (Pearson) for a 2D array
function Get-CorrelationMatrix {
    param($Data)
    # Accepts array of arrays (PowerShell style)
    $X = @()
    foreach ($row in $Data) { $X += ,([double[]]$row) }
    $n = $X.Count
    if ($n -eq 0) { return @() }
    $d = $X[0].Count
    $corr = @()
    # Compute means
    $means = @(for ($j=0;$j -lt $d;$j++) { ($X | ForEach-Object { $_[$j] } | Measure-Object -Average).Average })
    # Compute stds
    $stds = @(for ($j=0;$j -lt $d;$j++) {
        $mean = $means[$j]
        $vals = $X | ForEach-Object { $_[$j] }
        $std = [math]::Sqrt((($vals | ForEach-Object { ([double]$_ - $mean) * ([double]$_ - $mean) }) | Measure-Object -Sum).Sum / $n)
        if ($std -eq 0) { $std = 1 }
        $std
    })
    for ($i=0;$i -lt $d;$i++) {
        $row = New-Object 'double[]' $d
        for ($j=0;$j -lt $d;$j++) {
            $num = 0.0
            for ($k=0;$k -lt $n;$k++) {
                $num += ([double]$X[$k][$i] - $means[$i]) * ([double]$X[$k][$j] - $means[$j])
            }
            $row[$j] = $num / ($n * $stds[$i] * $stds[$j])
        }
        $corr += ,$row
    }
    return ,$corr
}
# data_processing.ps1
# Data preprocessing and feature-engineering utilities in PowerShell

function Split-TrainTest {
    param(
        [Parameter(Mandatory)]
        [object[]]$X, # array of feature vectors (array of arrays) or 2D matrix
        [Parameter(Mandatory)]
        [int[]]$y,     # labels
        [double]$TestSize = 0.2,
        [switch]$Stratify,
        [int]$Seed = 42,
        [int]$SampleSize = 0
    )
    if ($X.Count -ne $y.Count) { throw "X and y must have the same number of samples" }
    $total = $X.Count
    if ($SampleSize -lt 0) { throw "SampleSize must be non-negative" }
    if ($SampleSize -gt $total) { $SampleSize = $total }

    $rand = New-Object System.Random($Seed)

    # Build initial indices (0-based)
    $indices = 0..($total - 1)

    # If SampleSize requested, subsample indices first
    if ($SampleSize -gt 0 -and $SampleSize -lt $total) {
        if ($Stratify) {
            # Group indices by label
            $groups = @{}
            for ($i = 0; $i -lt $indices.Count; $i++) {
                $lab = $y[$i]
                if (-not $groups.ContainsKey($lab)) { $groups[$lab] = New-Object System.Collections.Generic.List[int] }
                $groups[$lab].Add($i)
            }
            # Desired per-group allocations (proportional)
            $alloc = @{}
            $sumAlloc = 0
            foreach ($k in $groups.Keys) {
                $desiredFloat = ($groups[$k].Count / [double]$total) * $SampleSize
                $floor = [math]::Floor($desiredFloat)
                $alloc[$k] = [int]$floor
                $sumAlloc += $alloc[$k]
            }
            # Distribute the remaining samples by fractional parts
            $remaining = $SampleSize - $sumAlloc
            if ($remaining -gt 0) {
                $fractions = @()
                foreach ($k in $groups.Keys) {
                    $desiredFloat = ($groups[$k].Count / [double]$total) * $SampleSize
                    $frac = $desiredFloat - [math]::Floor($desiredFloat)
                    $fractions += ,[PSCustomObject]@{Key=$k;Frac=$frac}
                }
                $fractions = $fractions | Sort-Object -Property Frac -Descending
                foreach ($f in $fractions) {
                    if ($remaining -le 0) { break }
                    if ($alloc[$f.Key] -lt $groups[$f.Key].Count) { $alloc[$f.Key]++; $remaining-- }
                }
            }
            # Now sample from each group
            $sampled = @()
            foreach ($k in $groups.Keys) {
                $list = $groups[$k] | ForEach-Object { $_ } | Sort-Object { $rand.Next() }
                $nTake = [math]::Min($alloc[$k], $list.Count)
                if ($nTake -gt 0) { $sampled += ,($list[0..($nTake - 1)]) }
            }
            $indices = $sampled
        } else {
            # Non-stratified sampling: shuffle and take first SampleSize
            $shuffled = $indices | Sort-Object { $rand.Next() }
            $indices = $shuffled[0..($SampleSize - 1)]
        }
    }

    # Ensure indices is a flat array of integers (avoid nested arrays from group sampling)
    $flat = @()
    foreach ($it in $indices) {
        if ($it -is [System.Array] -or $it -is [System.Collections.IEnumerable] -and -not ($it -is [string])) {
            foreach ($v in $it) { $flat += [int]$v }
        } else {
            $flat += [int]$it
        }
    }
    $indices = $flat

    # Now split indices into train/test based on TestSize ratio
    $sampleCount = $indices.Count
    if ($sampleCount -eq 0) { return [PSCustomObject]@{X_train=@(); y_train=@(); X_test=@(); y_test=@()} }

    # Global test count derived from sampleCount and TestSize
    $nTest = [int][math]::Round($sampleCount * $TestSize)
    if ($nTest -lt 0) { $nTest = 0 }
    if ($nTest -gt $sampleCount) { $nTest = $sampleCount }

    if ($Stratify) {
        # Build groups on the sampled indices
        $groups = @{}
        foreach ($idx in $indices) {
            $lab = $y[$idx]
            if (-not $groups.ContainsKey($lab)) { $groups[$lab] = @() }
            $groups[$lab] += $idx
        }
        # Determine per-group test allocation using floor and distribute remainder
        $alloc = @{}
        $sumFloor = 0
        foreach ($k in $groups.Keys) {
            $desiredFloat = ($groups[$k].Count / [double]$sampleCount) * $nTest
            $floor = [math]::Floor($desiredFloat)
            $alloc[$k] = [int]$floor
            $sumFloor += $alloc[$k]
        }
        $remaining = $nTest - $sumFloor
        if ($remaining -gt 0) {
            $fractions = @()
            foreach ($k in $groups.Keys) {
                $desiredFloat = ($groups[$k].Count / [double]$sampleCount) * $nTest
                $frac = $desiredFloat - [math]::Floor($desiredFloat)
                $fractions += ,[PSCustomObject]@{Key=$k;Frac=$frac}
            }
            $fractions = $fractions | Sort-Object -Property Frac -Descending
            foreach ($f in $fractions) {
                if ($remaining -le 0) { break }
                if ($alloc[$f.Key] -lt $groups[$f.Key].Count) { $alloc[$f.Key]++; $remaining-- }
            }
        }
        $trainIdx = @(); $testIdx = @()
        foreach ($k in $groups.Keys) {
            $list = $groups[$k] | Sort-Object { $rand.Next() }
            $nTake = [int]$alloc[$k]
            if ($nTake -gt $list.Count) { $nTake = $list.Count }
            if ($nTake -gt 0) { $testPart = $list[0..($nTake - 1)]; $trainPart = if ($nTake -lt $list.Count - 1) { $list[$nTake..($list.Count - 1)] } else { @() } } else { $testPart = @(); $trainPart = $list }
            $testIdx += $testPart
            $trainIdx += $trainPart
        }
        # In rare rounding cases, if total test count isn't equal to nTest, adjust by moving items between sets
        if ($testIdx.Count -ne $nTest) {
            $allSampled = ($trainIdx + $testIdx) | Sort-Object { $rand.Next() }
            $testIdx = $allSampled[0..([math]::Max(0,$nTest - 1))]
            if ($nTest -lt $allSampled.Count - 1) { $trainIdx = $allSampled[$nTest..($allSampled.Count - 1)] } else { $trainIdx = @() }
        }
    } else {
        # Shuffle sampled indices and split using global nTest
        $shuffled = $indices | Sort-Object { $rand.Next() }
        if ($nTest -eq 0) {
            $testIdx = @()
            $trainIdx = $shuffled
        } else {
            $testIdx = $shuffled[0..($nTest - 1)]
            if ($nTest -lt $shuffled.Count - 1) { $trainIdx = $shuffled[$nTest..($shuffled.Count - 1)] } else { $trainIdx = @() }
        }
    }

    $X_train = @()
    $y_train = @()
    foreach ($ii in $trainIdx) { $X_train += ,$X[$ii]; $y_train += $y[$ii] }
    $X_test = @()
    $y_test = @()
    foreach ($ii in $testIdx) { $X_test += ,$X[$ii]; $y_test += $y[$ii] }
    return [PSCustomObject]@{X_train=$X_train; y_train=$y_train; X_test=$X_test; y_test=$y_test}
}

function Fit-StandardScaler {
    param(
        [Parameter(Mandatory)]
        [double[][]]$X
    )
    $nFeatures = $X[0].Count
    $means = @(); $stds = @()
    for ($j = 0; $j -lt $nFeatures; $j++) {
        $col = $X | ForEach-Object { $_[$j] }
        $mean = ($col | Measure-Object -Average).Average
        $std = [math]::Sqrt((($col | ForEach-Object { ([double]$_ - $mean) * ([double]$_ - $mean) }) | Measure-Object -Sum).Sum / ($col.Count))
        if ($std -eq 0) { $std = 1 }
        $means += $mean; $stds += $std
    }
    return [PSCustomObject]@{Means=$means; Stds=$stds}
}

function Transform-StandardScaler {
    param(
        [double[][]]$X,
        [double[]]$Means,
        [double[]]$Stds
    )
    $out = @()
    foreach ($row in $X) {
        $r = @()
        for ($j = 0; $j -lt $row.Count; $j++) {
            $r += (([double]$row[$j] - $Means[$j]) / $Stds[$j])
        }
        $out += ,$r
    }
    return $out
}

function Fit-MinMaxScaler {
    param([double[][]]$X)
    $nFeatures = $X[0].Count
    $mins = @(); $maxs = @()
    for ($j = 0; $j -lt $nFeatures; $j++) {
        $col = $X | ForEach-Object { $_[$j] }
        $mins += ($col | Measure-Object -Minimum).Minimum
        $maxs += ($col | Measure-Object -Maximum).Maximum
    }
    return [PSCustomObject]@{Mins=$mins; Maxs=$maxs}
}

function Transform-MinMaxScaler {
    param([double[][]]$X, [double[]]$Mins, [double[]]$Maxs, [double]$FeatureRangeMin = 0.0, [double]$FeatureRangeMax = 1.0)
    $out = @()
    foreach ($row in $X) {
        $r = @()
        for ($j = 0; $j -lt $row.Count; $j++) {
            $min = $Mins[$j]; $max = $Maxs[$j]
            if ($max - $min -eq 0) { $r += $FeatureRangeMin; continue }
            $scaled = ($row[$j] - $min) / ($max - $min)
            $scaled = $scaled * ($FeatureRangeMax - $FeatureRangeMin) + $FeatureRangeMin
            $r += $scaled
        }
        $out += ,$r
    }
    return $out
}

function Fit-RobustScaler {
    param([double[][]]$X)
    $nFeatures = $X[0].Count
    $medians = @(); $iqrs = @()
    for ($j = 0; $j -lt $nFeatures; $j++) {
        $col = ($X | ForEach-Object { $_[$j] }) | Sort-Object
        $n = $col.Count
        $median = if ($n % 2 -eq 1) { $col[([int]([math]::Floor($n/2)))] } else { (($col[$n/2 - 1] + $col[$n/2]) / 2) }
        $q1 = $col[([int]([math]::Floor($n * 0.25)))]
        $q3 = $col[([int]([math]::Floor($n * 0.75)))]
        $iqr = $q3 - $q1
        if ($iqr -eq 0) { $iqr = 1 }
        $medians += $median; $iqrs += $iqr
    }
    return [PSCustomObject]@{Medians=$medians; IQRs=$iqrs}
}

function Transform-RobustScaler {
    param([double[][]]$X, [double[]]$Medians, [double[]]$IQRs)
    $out = @()
    foreach ($row in $X) {
        $r = @()
        for ($j = 0; $j -lt $row.Count; $j++) {
            $r += (([double]$row[$j] - $Medians[$j]) / $IQRs[$j])
        }
        $out += ,$r
    }
    return $out
}

# Simple SMOTE implementation for binary classification. This is a very small-scale, not-optimized version.
function Invoke-SMOTE {
    param(
        [double[][]]$X,
        [int[]]$y,
        [int]$N = 100, # percentage of new synthetic samples per minority sample
        [int]$k = 5,
        [int]$Seed = 42
    )
    # Optimized SMOTE: vectorized neighbor selection using KD-tree-like approach (approximate via sorting per feature)
    $rand = New-Object System.Random($Seed)
    # identify minority class
    $counts = @{}
    for ($i = 0; $i -lt $y.Count; $i++) { if (-not $counts.ContainsKey($y[$i])) { $counts[$y[$i]] = 0 }; $counts[$y[$i]]++ }
    $sortedCounts = $counts.GetEnumerator() | Sort-Object -Property Value
    $minorLabel = $sortedCounts[0].Key
    $minorIdx = 0..($y.Count - 1) | Where-Object { $y[$_] -eq $minorLabel }
    $nMinor = $minorIdx.Count
    if ($nMinor -eq 0) { throw 'No minority samples found' }
    $nSynthTotal = [math]::Floor($nMinor * ($N / 100))
    $syntheticX = New-Object 'System.Collections.Generic.List[object[]]'
    $syntheticY = New-Object 'System.Collections.Generic.List[int]'
    # Precompute neighbor candidates using euclidean distance on a random subset of features for speed
    $featureCount = $X[0].Count
    for ($i = 0; $i -lt $nMinor; $i++) {
        $idx = $minorIdx[$i]
        # find k neighbors among minority set
        $dlist = New-Object 'System.Collections.Generic.List[System.Tuple[int,double]]'
        for ($j = 0; $j -lt $nMinor; $j++) {
            if ($i -eq $j) { continue }
            $idx2 = $minorIdx[$j]
            $sum = 0.0
            for ($f = 0; $f -lt $featureCount; $f++) { $diff = [double]$X[$idx][$f] - [double]$X[$idx2][$f]; $sum += $diff * $diff }
            $d = [math]::Sqrt($sum)
            $tupleType = [System.Tuple[int,double]]
            $dlist.Add([System.Tuple]::Create($idx2, $d))
        }
        $neighbors = $dlist | Sort-Object -Property Item2 | Select-Object -First $k
        $nToGen = [math]::Ceiling($N / 100)
        for ($g = 0; $g -lt $nToGen; $g++) {
            $nbr = $neighbors[$rand.Next(0,$neighbors.Count)].Item1
            $gap = $rand.NextDouble()
            $synth = New-Object 'object[]' ($featureCount)
            for ($f = 0; $f -lt $featureCount; $f++) { $synth[$f] = [double]$X[$idx][$f] + $gap * ([double]$X[$nbr][$f] - [double]$X[$idx][$f]) }
            $syntheticX.Add($synth)
            $syntheticY.Add($minorLabel)
        }
    }
    $X_new = @($X + $syntheticX)
    $y_new = @($y + $syntheticY)
    return [PSCustomObject]@{X=$X_new; y=$y_new}
}

function Invoke-KFoldCV {
    param(
        [Parameter(Mandatory)] [object[][]]$X,
        [Parameter(Mandatory)] [int[]]$y,
        [int]$K = 5,
        [int]$Seed = 42,
        [switch]$Stratify
    )
    if ($X.Count -ne $y.Count) { throw 'X and y must have same length' }
    $rand = New-Object System.Random($Seed)
    $indices = 0..($X.Count - 1)
    if ($Stratify) {
        $groups = @{}
        for ($i=0; $i -lt $indices.Count; $i++) { $lab = $y[$i]; if (-not $groups.ContainsKey($lab)) { $groups[$lab] = New-Object 'System.Collections.Generic.List[int]' }; $groups[$lab].Add($i) }
        # create folds
        $folds = @()
        for ($i = 0; $i -lt $K; $i++) { $folds += ,@( ) }
        foreach ($g in $groups.Keys) {
            $list = $groups[$g] | Sort-Object { $rand.Next() }
            for ($i = 0; $i -lt $list.Count; $i++) { $folds[$i % $K] += $list[$i] }
        }
    } else {
        $shuffled = $indices | Sort-Object { $rand.Next() }
        $folds = @()
        for ($i = 0; $i -lt $K; $i++) { $folds += ,@( ) }
        for ($i = 0; $i -lt $shuffled.Count; $i++) { $folds[$i % $K] += $shuffled[$i] }
    }
    $results = @()
    for ($i = 0; $i -lt $K; $i++) {
        $testIdx = $folds[$i]
        $trainIdx = @()
        for ($j = 0; $j -lt $K; $j++) { if ($j -ne $i) { $trainIdx += $folds[$j] } }
        $X_train = $trainIdx | ForEach-Object { $X[$_] }
        $y_train = $trainIdx | ForEach-Object { $y[$_] }
        $X_test = $testIdx | ForEach-Object { $X[$_] }
        $y_test = $testIdx | ForEach-Object { $y[$_] }
        $results += ,([PSCustomObject]@{Fold=$i; X_train=$X_train; y_train=$y_train; X_test=$X_test; y_test=$y_test})
    }
    return $results
}

# Feature selection methods: We'll provide wrappers that compute simple scores and return selected feature indices.
function Select-ByANOVA {
    param([double[][]]$X, [int[]]$y, [int]$k = 10)
    $nFeatures = $X[0].Count
    $scores = @()
    for ($j = 0; $j -lt $nFeatures; $j++) {
        $groups = @{}
        for ($i = 0; $i -lt $X.Count; $i++) {
            $lab = $y[$i]
            if (-not $groups.ContainsKey($lab)) { $groups[$lab] = @() }
            $groups[$lab] += $X[$i][$j]
        }
        $grandMean = ($X | ForEach-Object { $_[$j] } | Measure-Object -Average).Average
        $ssb = 0; $ssw = 0
        foreach ($g in $groups.Keys) {
            $n = $groups[$g].Count
            $mean = ($groups[$g] | Measure-Object -Average).Average
            $ssb += $n * ([double]$mean - $grandMean) * ([double]$mean - $grandMean)
            $ssw += ($groups[$g] | ForEach-Object { ([double]$_ - $mean) * ([double]$_ - $mean) }) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        }
        if ($ssw -eq 0) { $f = 0 } else { $f = ($ssb / ($groups.Count - 1)) / ($ssw / ($X.Count - $groups.Count)) }
        $scores += $f
    }
    $indices = 0..($nFeatures - 1) | Sort-Object -Property { -1 * $scores[$_] } | Select-Object -First $k
    return $indices
}

function Select-ByMutualInformation {
    param([double[][]]$X, [int[]]$y, [int]$k = 10)
    # Mutual information estimation via discretization (bins)
    $nFeatures = $X[0].Count
    $scores = @()
    for ($j = 0; $j -lt $nFeatures; $j++) {
        $col = $X | ForEach-Object { $_[$j] }
        $bins = 10
        $min = ($col | Measure-Object -Minimum).Minimum
        $max = ($col | Measure-Object -Maximum).Maximum
        if ($max - $min -eq 0) { $scores += 0; continue }
        $edges = for ($b = 0; $b -le $bins; $b++) { $min + ($b / $bins) * ($max - $min) }
        $joint = @{}
        $px = @{}
        $py = @{}
        for ($i = 0; $i -lt $col.Count; $i++) {
            $val = $col[$i]
            $binIdx = [math]::Floor((($val - $min) / ($max - $min)) * $bins)
            if ($binIdx -lt 0) { $binIdx = 0 } elseif ($binIdx -gt $bins - 1) { $binIdx = $bins - 1 }
            $lab = $y[$i]
            $jointKey = "$binIdx|$lab"
            if (-not $joint.ContainsKey($jointKey)) { $joint[$jointKey] = 0 }
            $joint[$jointKey]++
            if (-not $px.ContainsKey($binIdx)) { $px[$binIdx] = 0 }
            $px[$binIdx]++
            if (-not $py.ContainsKey($lab)) { $py[$lab] = 0 }
            $py[$lab]++
        }
        $mi = 0.0
        forEach ($kKey in $joint.Keys) {
            $parts = $kKey -split '\|'
            $bx = [int]$parts[0]; $ly = [int]$parts[1]
            $p_xy = $joint[$kKey] / $col.Count
            $p_x = $px[$bx] / $col.Count
            $p_y = $py[$ly] / $col.Count
            $mi += $p_xy * [math]::Log($p_xy / ($p_x * $p_y) + 1e-12)
        }
        $scores += $mi
    }
    $indices = 0..($nFeatures - 1) | Sort-Object -Property { -1 * $scores[$_] } | Select-Object -First $k
    return $indices
}

# Random forest feature importance (very simple random forest using decision stumps and bagging)
function Get-RandomForestFeatureImportance {
    param([double[][]]$X, [int[]]$y, [int]$nTrees = 10, [int]$Seed = 42)
    $rand = New-Object System.Random($Seed)
    $nFeatures = $X[0].Count
    $importances = @(for ($i=0;$i -lt $nFeatures;$i++) { 0 })
    for ($t = 0; $t -lt $nTrees; $t++) {
        # bootstrap sample
        $indices = 0..($X.Count - 1) | ForEach-Object { $rand.Next(0,$X.Count) }
        $Xb = $indices | ForEach-Object { $X[$_] }
        $yb = $indices | ForEach-Object { $y[$_] }
        # for each feature, fit a stump (threshold) and measure impurity decrease
        for ($f = 0; $f -lt $nFeatures; $f++) {
            $col = $Xb | ForEach-Object { $_[$f] }
            $sortedIdx = 0..($col.Count -1) | Sort-Object -Property { $col[$_] }
            $bestGain = 0
            for ($i = 1; $i -lt $col.Count; $i++) {
                $thr = ($col[$sortedIdx[$i]] + $col[$sortedIdx[$i-1]]) / 2
                $leftIdx = $sortedIdx | Where-Object { $col[$_] -le $thr }
                $rightIdx = $sortedIdx | Where-Object { $col[$_] -gt $thr }
                if ($leftIdx.Count -eq 0 -or $rightIdx.Count -eq 0) { continue }
                $gini = {
                    param($labels)
                    $n = $labels.Count
                    $vals = @{}
                    foreach ($l in $labels) { if (-not $vals.ContainsKey($l)) { $vals[$l] = 0 }; $vals[$l]++ }
                    $imp = 1.0
                    foreach ($k in $vals.Keys) { $p = $vals[$k] / $n; $imp -= $p * $p }
                    return $imp
                }
                $impParent = &$gini -labels $yb
                $impLeft = &$gini -labels ($leftIdx | ForEach-Object { $yb[$_] })
                $impRight = &$gini -labels ($rightIdx | ForEach-Object { $yb[$_] })
                $gain = $impParent - (($leftIdx.Count / $col.Count) * $impLeft + ($rightIdx.Count / $col.Count) * $impRight)
                if ($gain -gt $bestGain) { $bestGain = $gain }
            }
            $importances[$f] += $bestGain
        }
    }
    # normalize
    $sum = ($importances | Measure-Object -Sum).Sum
    if ($sum -eq 0) { return $importances }
    return $importances | ForEach-Object { $_ / $sum }
}

function Compute-PCA {
    param(
        [Parameter(Mandatory)][double[][]]$X,
        [int]$k = 10,
        [int]$MaxIter = 100,
        [double]$Tol = 1e-6,
        [int]$Seed = 42
    )
    # X: array of samples (n) each an array of features (p)
    $n = $X.Count
    if ($n -eq 0) { throw 'Empty X' }
    $p = $X[0].Count
    $mean = New-Object 'double[]' $p
    for ($j=0;$j -lt $p;$j++) { $sum = 0.0; for ($i=0;$i -lt $n;$i++) { $sum += [double]$X[$i][$j] }; $mean[$j] = $sum / $n }
    # center data
    $Xc = New-Object 'object[]' $n
    for ($i=0;$i -lt $n;$i++) { $row = New-Object 'double[]' $p; for ($j=0;$j -lt $p;$j++) { $row[$j] = [double]$X[$i][$j] - $mean[$j] }; $Xc[$i] = $row }

    $rand = New-Object System.Random($Seed)
    $k = [math]::Min($k, $p)
    $components = New-Object 'object[]' $k

    for ($comp=0;$comp -lt $k;$comp++) {
        # initialize random vector
        $v = New-Object 'double[]' $p
        for ($j=0;$j -lt $p;$j++) { $v[$j] = $rand.NextDouble() - 0.5 }
        # power iteration on covariance via Xc
        for ($it=0;$it -lt $MaxIter;$it++) {
            # y = Xc * v  (n)
            $y = New-Object 'double[]' $n
            for ($i=0;$i -lt $n;$i++) {
                $sum = 0.0
                $row = $Xc[$i]
                for ($j=0;$j -lt $p;$j++) { $sum += $row[$j] * $v[$j] }
                $y[$i] = $sum
            }
            # z = Xc^T * y  (p)
            $z = New-Object 'double[]' $p
            for ($j=0;$j -lt $p;$j++) {
                $sum = 0.0
                for ($i=0;$i -lt $n;$i++) { $sum += $Xc[$i][$j] * $y[$i] }
                $z[$j] = $sum
            }
            # normalize z
            $norm = 0.0
            for ($j=0;$j -lt $p;$j++) { $norm += $z[$j] * $z[$j] }
            $norm = [math]::Sqrt($norm)
            if ($norm -eq 0) { break }
            for ($j=0;$j -lt $p;$j++) { $z[$j] = $z[$j] / $norm }
            # check convergence
            $diff = 0.0
            for ($j=0;$j -lt $p;$j++) { $d = $z[$j] - $v[$j]; $diff += $d * $d }
            if ([math]::Sqrt($diff) -lt $Tol) { $v = $z; break }
            $v = $z
        }
        # store component
        $components[$comp] = $v
        # deflate Xc by removing projection onto v
        for ($i=0;$i -lt $n;$i++) {
            $proj = 0.0
            for ($j=0;$j -lt $p;$j++) { $proj += $Xc[$i][$j] * $v[$j] }
            for ($j=0;$j -lt $p;$j++) { $Xc[$i][$j] = $Xc[$i][$j] - $proj * $v[$j] }
        }
    }
    return [PSCustomObject]@{Components=$components; Mean=$mean}
}

function Project-PCA {
    param(
        [Parameter(Mandatory)][double[]]$Vector,
        [Parameter(Mandatory)][object[]]$Components,
        [Parameter(Mandatory)][double[]]$Mean
    )
    $p = $Vector.Count
    $k = $Components.Count
    $center = New-Object 'double[]' $p
    for ($j=0;$j -lt $p;$j++) { $center[$j] = [double]$Vector[$j] - $Mean[$j] }
    $out = New-Object 'double[]' $k
    for ($c=0;$c -lt $k;$c++) {
        $comp = [double[]]$Components[$c]
        $sum = 0.0
        for ($j=0;$j -lt $p;$j++) { $sum += $center[$j] * $comp[$j] }
        $out[$c] = $sum
    }
    return $out
}

if ($PSModuleInfo) { Export-ModuleMember -Function Split-TrainTest,Fit-StandardScaler,Transform-StandardScaler,Fit-MinMaxScaler,Transform-MinMaxScaler,Fit-RobustScaler,Transform-RobustScaler,Invoke-SMOTE,Select-ByANOVA,Select-ByMutualInformation,Get-RandomForestFeatureImportance,Compute-PCA,Project-PCA }

# Batching utilities
function Get-Batches {
    param(
        [Parameter(Mandatory)] [object[]]$X,
        [Parameter(Mandatory)] [object[]]$y,
        [int]$BatchSize = 32,
        [switch]$Shuffle,
        [int]$Seed = 42
    )
    if ($X.Count -ne $y.Count) { throw 'X and y must have same length' }
    $indices = 0..($X.Count - 1)
    $rand = New-Object System.Random($Seed)
    if ($Shuffle) { $indices = $indices | Sort-Object { $rand.Next() } }
    $batches = @()
    for ($i = 0; $i -lt $indices.Count; $i += $BatchSize) {
        $batchIdx = $indices[$i..([math]::Min($i + $BatchSize - 1, $indices.Count - 1))]
        $Xb = $batchIdx | ForEach-Object { $X[$_] }
        $yb = $batchIdx | ForEach-Object { $y[$_] }
        $batches += ,([PSCustomObject]@{X=$Xb; y=$yb})
    }
    return $batches
}

# Convert categorical (nominal) values to integer codes (label encoding)
function Convert-ToNominalEncoding {
    param(
        [Parameter(Mandatory)] [object[]]$Values,
        [hashtable]$Mapping = $null
    )
    # If mapping is provided, use it; otherwise build from unique values in order of appearance
    if ($null -eq $Mapping) { $Mapping = @{} }
    $nextCode = 0
    foreach ($v in $Values) {
        if (-not $Mapping.ContainsKey($v)) {
            $Mapping[$v] = $nextCode
            $nextCode++
        }
    }
    $encoded = $Values | ForEach-Object { [int]$Mapping[$_] }
    return [PSCustomObject]@{Encoded=$encoded; Mapping=$Mapping}
}

# Convert categorical values to one-hot encoded vectors
function Convert-ToOneHot {
    param(
        [Parameter(Mandatory)] [object[]]$Values,
        [hashtable]$Mapping = $null
    )
    # Build or reuse mapping (category -> index)
    if ($null -eq $Mapping) { $Mapping = @{} }
    $nextIdx = 0
    foreach ($v in $Values) {
        if (-not $Mapping.ContainsKey($v)) {
            $Mapping[$v] = $nextIdx
            $nextIdx++
        }
    }
    $nCats = $Mapping.Count
    $out = @()
    foreach ($v in $Values) {
        $vec = New-Object 'double[]' $nCats
        for ($i=0; $i -lt $nCats; $i++) { $vec[$i] = 0.0 }
        $idx = $Mapping[$v]
        $vec[$idx] = 1.0
        $out += ,$vec
    }
    return [PSCustomObject]@{OneHot=$out; Mapping=$Mapping}
}

# Normalize single image matrix to [0,1] or mean-std
function Normalize-Image {
    param(
        [Parameter(Mandatory)] [double[][]]$Image,
        [ValidateSet('minmax','standard')]
        [string]$Method = 'minmax'
    )
    $rows = $Image.Count
    $cols = $Image[0].Count
    if ($Method -eq 'minmax') {
        $min = [double]::PositiveInfinity; $max = [double]::NegativeInfinity
        for ($i = 0; $i -lt $rows; $i++) { for ($j = 0; $j -lt $cols; $j++) { $v = [double]$Image[$i][$j]; if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } } }
        $range = $max - $min
        if ($range -eq 0) { return $Image }
        $out = New-Object 'object[]' $rows
        for ($i = 0; $i -lt $rows; $i++) {
            $r = New-Object 'double[]' $cols
            for ($j = 0; $j -lt $cols; $j++) { $r[$j] = ([double]$Image[$i][$j] - $min) / $range }
            $out[$i] = $r
        }
        return ,$out
    } else {
        # standardize
        $sum = 0.0; $count = 0
        for ($i = 0; $i -lt $rows; $i++) { for ($j = 0; $j -lt $cols; $j++) { $sum += [double]$Image[$i][$j]; $count++ } }
        $mean = $sum / $count
        $sq = 0.0
        for ($i = 0; $i -lt $rows; $i++) { for ($j = 0; $j -lt $cols; $j++) { $d = [double]$Image[$i][$j] - $mean; $sq += $d * $d } }
        $std = [math]::Sqrt($sq / $count)
        if ($std -eq 0) { $std = 1 }
        $out = New-Object 'object[]' $rows
        for ($i = 0; $i -lt $rows; $i++) {
            $r = New-Object 'double[]' $cols
            for ($j = 0; $j -lt $cols; $j++) { $r[$j] = ([double]$Image[$i][$j] - $mean) / $std }
            $out[$i] = $r
        }
        return ,$out
    }
}

# Normalize dataset of images
function Normalize-Dataset {
    param(
        [Parameter(Mandatory)] [object[]]$Dataset, # array of PSCustomObject with Matrix property or double[][]
        [ValidateSet('minmax','standard')]
        [string]$Method = 'minmax'
    )
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in $Dataset) {
        if ($item -is [PSCustomObject] -and $item.PSObject.Properties.Name -contains 'Matrix') {
            $matrix = $item.Matrix
            $norm = Normalize-Image -Image $matrix -Method $Method
            $out.Add([PSCustomObject]@{Path=$item.Path; Matrix=$norm})
        } else {
            $norm = Normalize-Image -Image $item -Method $Method
            $out.Add($norm)
        }
    }
    return $out
}

# Batch generator for streaming large datasets
function Get-BatchGenerator {
    param(
        [Parameter(Mandatory)] [string]$Dir,
        [ValidateSet('csv','txt','images')][string]$Type = 'images',
        [int]$BatchSize = 32,
        [switch]$Shuffle,
        [int]$Seed = 42,
        [switch]$Grayscale
    )
    $files = if ($Type -eq 'images') { Get-ChildItem -Path $Dir -Include *.png,*.jpg,*.jpeg -File } elseif ($Type -eq 'csv') { Get-ChildItem -Path $Dir -Filter '*.csv' } else { Get-ChildItem -Path $Dir -Filter '*.txt' }
    $indices = 0..($files.Count - 1)
    $rand = New-Object System.Random($Seed)
    if ($Shuffle) { $indices = $indices | Sort-Object { $rand.Next() } }
    # Return an IEnumerator that streams batches on MoveNext/Current
    # BatchEnumerator class removed for compatibility
    $fileArray = $files
    # Return batches as arrays (no IEnumerator)
    $batches = @()
    for ($i = 0; $i -lt $fileArray.Count; $i += $BatchSize) {
        $end = [math]::Min($i + $BatchSize - 1, $fileArray.Count - 1)
        $batchFiles = $fileArray[$i..$end]
        $X = @(); $y = @()
        foreach ($f in $batchFiles) {
            if ($Type -eq 'images') { $mat = Read-ImageToMatrix -Path $f.FullName -Grayscale:($Grayscale) } elseif ($Type -eq 'csv') { $mat = Read-CsvToMatrix -Path $f.FullName } else { $mat = Read-TxtToMatrix -Path $f.FullName }
            $X += ,$mat
            $y += 0
        }
        $batches += ,([PSCustomObject]@{X=$X; y=$y})
    }
    return $batches
}


# Prefetching batch enumerator: uses BlockingCollection and a background thread to load batches
function Get-PrefetchingBatchGenerator {
    param(
        [Parameter(Mandatory)] [string]$Dir,
        [ValidateSet('csv','txt','images')][string]$Type = 'images',
        [int]$BatchSize = 32,
        [int]$PrefetchBatches = 4,
        [switch]$Shuffle,
        [int]$Seed = 42,
        [switch]$Grayscale,
        [System.Threading.CancellationTokenSource]$CancellationTokenSource
    )
    Add-Type -AssemblyName 'System.Collections'
    Add-Type -AssemblyName 'System.Collections.Concurrent'

    if ($Type -eq 'images') { $files = Get-ChildItem -Path $Dir -Include *.png,*.jpg,*.jpeg -File } elseif ($Type -eq 'csv') { $files = Get-ChildItem -Path $Dir -Filter '*.csv' } else { $files = Get-ChildItem -Path $Dir -Filter '*.txt' }
    $indices = 0..($files.Count - 1)
    $rand = New-Object System.Random($Seed)
    if ($Shuffle) { $indices = $indices | Sort-Object { $rand.Next() } }
    $fileArray = $indices | ForEach-Object { $files[$_] }

    # Blocking collection with bounded capacity
    $buffer = New-Object 'System.Collections.Concurrent.BlockingCollection[object]' ([int]($PrefetchBatches))

    # Producer thread
    $producerScript = {
        param($fileArray, $BatchSize, $Type, $Grayscale, $buffer)
        try {
            for ($i = 0; $i -lt $fileArray.Count; $i += $BatchSize) {
                $end = [math]::Min($i + $BatchSize - 1, $fileArray.Count - 1)
                $batch = $fileArray[$i..$end]
                $X = @(); $y = @()
                foreach ($f in $batch) {
                    if ($Type -eq 'images') { $mat = Read-ImageToMatrix -Path $f.FullName -Grayscale:$Grayscale } elseif ($Type -eq 'csv') { $mat = Read-CsvToMatrix -Path $f.FullName } else { $mat = Read-TxtToMatrix -Path $f.FullName }
                    $X += ,$mat
                    $y += 0
                }
                $buffer.Add([PSCustomObject]@{X=$X; y=$y})
            }
        } finally {
            $buffer.CompleteAdding()
        }
    }

    $threadStart = [System.Threading.ThreadStart]::new([Action]{})
    # build a ThreadStart delegate by creating a closure via a helper
    $del = [System.Delegate]::CreateDelegate([System.Threading.ThreadStart], $producerScript, 'Invoke')
    # Fallback: use a lambda wrapper to start the producer with parameters via Thread
    $ts = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        & $producerScript $fileArray $BatchSize $Type $Grayscale $buffer
    })
    $ts.IsBackground = $true
    $ts.Start()

    # Enumerator that consumes from buffer
    # PrefetchingBatchEnumerator class removed for compatibility
    # Return batches as arrays (no IEnumerator)
    $batches = @()
    while (-not $buffer.IsCompleted) {
        $item = $null
        if ($buffer.TryTake([ref]$item, 500)) {
            $batches += ,$item
        }
    }
    return $batches
}


# Cancellation helpers
function New-CancellationTokenSource {
    param([int]$TimeoutMs = 0)
    $cts = [System.Threading.CancellationTokenSource]::new()
    if ($TimeoutMs -gt 0) { $cts.CancelAfter($TimeoutMs) }
    return $cts
}

function Cancel-CancellationTokenSource {
    param([System.Threading.CancellationTokenSource]$CTS)
    if ($CTS -ne $null) { $CTS.Cancel() }
}


# Image resizing and augmentation helpers (operate on double[][] matrices)
function Resize-Image {
    param(
        [double[][]]$Image,
        [int]$NewWidth,
        [int]$NewHeight,
        [ValidateSet('nearest','bilinear')]
        [string]$Method = 'nearest'
    )
    $oldH = $Image.Count; $oldW = $Image[0].Count
    $out = New-Object 'object[]' $NewHeight
    for ($y = 0; $y -lt $NewHeight; $y++) {
        $row = New-Object 'double[]' $NewWidth
        $srcY = ($y + 0.5) * $oldH / $NewHeight - 0.5
        for ($x = 0; $x -lt $NewWidth; $x++) {
            $srcX = ($x + 0.5) * $oldW / $NewWidth - 0.5
            if ($Method -eq 'nearest') {
                $ix = [math]::Min([math]::Max([math]::Round($srcX),0), $oldW -1)
                $iy = [math]::Min([math]::Max([math]::Round($srcY),0), $oldH -1)
                $row[$x] = $Image[$iy][$ix]
            } else {
                $x0 = [math]::Floor($srcX); $x1 = [math]::Min($x0 + 1, $oldW - 1); $y0 = [math]::Floor($srcY); $y1 = [math]::Min($y0 + 1, $oldH - 1)
                $dx = $srcX - $x0; $dy = $srcY - $y0
                $v00 = $Image[$y0][$x0]; $v10 = $Image[$y0][$x1]; $v01 = $Image[$y1][$x0]; $v11 = $Image[$y1][$x1]
                $row[$x] = $v00 * (1 - $dx) * (1 - $dy) + $v10 * $dx * (1 - $dy) + $v01 * (1 - $dx) * $dy + $v11 * $dx * $dy
            }
        }
        $out[$y] = $row
    }
	return ,$out
}

# Lightweight DataFrame-like API (subset of pandas functionality)
function New-DataFrame {
    param([object[][]]$Data, [string[]]$Columns)
    $df = [PSCustomObject]@{}
    $df.Rows = $Data
    if ($Columns -ne $null) { $df.Columns = $Columns } else { $df.Columns = (0..($Data[0].Count - 1) | ForEach-Object { "C$_" }) }
    $df | Add-Member -MemberType ScriptMethod -Name Head -Value { param($n=5) $this.Rows[0..([math]::Min($n-1, $this.Rows.Count-1))] }
    $df | Add-Member -MemberType ScriptMethod -Name Tail -Value { param($n=5) $this.Rows[([math]::Max(0,$this.Rows.Count-$n))..($this.Rows.Count-1)] }
    $df | Add-Member -MemberType ScriptMethod -Name Shape -Value { return ,@($this.Rows.Count, $this.Columns.Count) }
    $df | Add-Member -MemberType ScriptMethod -Name ColumnsList -Value { return $this.Columns }
    $df | Add-Member -MemberType ScriptMethod -Name Describe -Value {
        $cols = @{}
        for ($j=0;$j -lt $this.Columns.Count;$j++) {
            $vals = $this.Rows | ForEach-Object { [double]$_[$j] }
            $cols[$this.Columns[$j]] = [PSCustomObject]@{count=$vals.Count; mean=([math]::Round((($vals | Measure-Object -Average).Average),4)); std=([math]::Round([math]::Sqrt((($vals | ForEach-Object { ($_ - (($vals | Measure-Object -Average).Average)) * ($_ - (($vals | Measure-Object -Average).Average)) }) | Measure-Object -Sum).Sum / $vals.Count),4)); min=($vals | Measure-Object -Minimum).Minimum; max=($vals | Measure-Object -Maximum).Maximum }
        }
        return $cols
    }
    $df | Add-Member -MemberType ScriptMethod -Name Info -Value { Write-Host ("Rows: {0}, Cols: {1}" -f $this.Rows.Count, $this.Columns.Count) }
    $df | Add-Member -MemberType ScriptMethod -Name Select -Value { param($cols) $idx = $cols | ForEach-Object { if ($_ -is [int]) { $_ } else { [array]::IndexOf($this.Columns, $_) } }; $out = $this.Rows | ForEach-Object { $row = @(); foreach ($i in $idx) { $row += $_[$i] }; ,$row }; return $out }
    $df | Add-Member -MemberType ScriptMethod -Name Drop -Value { param($cols) $idx = $cols | ForEach-Object { if ($_ -is [int]) { $_ } else { [array]::IndexOf($this.Columns, $_) } }; $newCols = @(); for ($i=0;$i -lt $this.Columns.Count;$i++) { if ($idx -notcontains $i) { $newCols += $this.Columns[$i] } }; $newRows = $this.Rows | ForEach-Object { $r = @(); for ($i=0;$i -lt $_.Count;$i++) { if ($idx -notcontains $i) { $r += $_[$i] } }; ,$r }; return New-DataFrame -Data $newRows -Columns $newCols }
    $df | Add-Member -MemberType ScriptMethod -Name Sort -Value { param($by, $desc=$false) $i = if ($by -is [int]) { $by } else { [array]::IndexOf($this.Columns, $by) }; $sorted = $this.Rows | Sort-Object -Property { $_[$i] } -Descending:$desc; return New-DataFrame -Data $sorted -Columns $this.Columns }
    $df | Add-Member -MemberType ScriptMethod -Name FillNA -Value { param($value) $new = $this.Rows | ForEach-Object { $r = $_; for ($i=0;$i -lt $r.Count;$i++) { if ($r[$i] -eq $null) { $r[$i] = $value } }; ,$r }; return New-DataFrame -Data $new -Columns $this.Columns }
    $df | Add-Member -MemberType ScriptMethod -Name IsNA -Value { $this.Rows | ForEach-Object { $_ | ForEach-Object { $_ -eq $null } } }
    $df | Add-Member -MemberType ScriptMethod -Name ToCsv -Value { param($path) $lines = @(); $lines += ($this.Columns -join ','); foreach ($r in $this.Rows) { $lines += ($r -join ',') }; Set-Content -Path $path -Value $lines }
    $df | Add-Member -MemberType ScriptMethod -Name ToArray -Value { return $this.Rows }
    $df | Add-Member -MemberType ScriptMethod -Name GroupByAggregate -Value { param($by, $agg) $i = if ($by -is [int]) { $by } else { [array]::IndexOf($this.Columns, $by) }; $groups = @{}; foreach ($r in $this.Rows) { $k = $r[$i]; if (-not $groups.ContainsKey($k)) { $groups[$k] = @() }; $groups[$k] += ,$r }; $out = @(); foreach ($k in $groups.Keys) { $vals = $groups[$k] | ForEach-Object { $_[$agg] }; $out += ,[PSCustomObject]@{Group=$k; Mean=($vals | Measure-Object -Average).Average } }; return $out }
    $df | Add-Member -MemberType ScriptMethod -Name Merge -Value { param($other, $on) # simple inner join
        $i1 = if ($on -is [int]) { $on } else { [array]::IndexOf($this.Columns, $on) }
        $i2 = if ($on -is [int]) { $on } else { [array]::IndexOf($other.Columns, $on) }
        $out = @()
        foreach ($r1 in $this.Rows) { foreach ($r2 in $other.Rows) { if ($r1[$i1] -eq $r2[$i2]) { $out += ,($r1 + $r2) } } }
        $cols = $this.Columns + $other.Columns
        return New-DataFrame -Data $out -Columns $cols
    }
    $df | Add-Member -MemberType ScriptMethod -Name Concat -Value { param($others) $all = $this.Rows; foreach ($o in $others) { $all += $o.Rows }; return New-DataFrame -Data $all -Columns $this.Columns }
    return $df
}

function From-CsvToDataFrame { param([string]$Path) $lines = Get-Content $Path; $cols = ($lines[0] -split ','); $rows = $lines[1..($lines.Count-1)] | ForEach-Object { ($_ -split ',') } ; return New-DataFrame -Data $rows -Columns $cols }


if ($MyInvocation.InvocationName -eq '.') {
    if ($PSModuleInfo) { Export-ModuleMember -Function Get-CorrelationMatrix,Split-TrainTest,Convert-ToNominalEncoding,Convert-ToOneHot }
}

function Augment-Flip {
    param([double[][]]$Image, [ValidateSet('horizontal','vertical')] [string]$Mode = 'horizontal')
    $h = $Image.Count; $w = $Image[0].Count
    $out = New-Object 'object[]' $h
    for ($y = 0; $y -lt $h; $y++) {
        $row = New-Object 'double[]' $w
        for ($x = 0; $x -lt $w; $x++) {
            if ($Mode -eq 'horizontal') { $row[$x] = $Image[$y][$w - 1 - $x] } else { $row[$x] = $Image[$h - 1 - $y][$x] }
        }
        $out[$y] = $row
    }
    return ,$out
}

function Augment-Rotate {
    param([double[][]]$Image, [ValidateSet(0,90,180,270)] [int]$Angle)
    $h = $Image.Count; $w = $Image[0].Count
    switch ($Angle) {
        0 { return ,$Image }
        90 {
            $out = New-Object 'object[]' $w
            for ($x = 0; $x -lt $w; $x++) { $row = New-Object 'double[]' $h; for ($y = 0; $y -lt $h; $y++) { $row[$y] = $Image[$h - 1 - $y][$x] }; $out[$x] = $row }
            return ,$out
        }
        180 {
            $out = New-Object 'object[]' $h
            for ($y = 0; $y -lt $h; $y++) { $row = New-Object 'double[]' $w; for ($x = 0; $x -lt $w; $x++) { $row[$x] = $Image[$h - 1 - $y][$w - 1 - $x] }; $out[$y] = $row }
            return ,$out
        }
        270 {
            $out = New-Object 'object[]' $w
            for ($x = 0; $x -lt $w; $x++) { $row = New-Object 'double[]' $h; for ($y = 0; $y -lt $h; $y++) { $row[$y] = $Image[$y][$w - 1 - $x] }; $out[$x] = $row }
            return ,$out
        }
    }
}

function Augment-Crop {
    param([double[][]]$Image, [int]$CropWidth, [int]$CropHeight, [switch]$Center)
    $h = $Image.Count; $w = $Image[0].Count
    if ($CropWidth -gt $w -or $CropHeight -gt $h) { throw 'Crop size must be <= image size' }
    if ($Center) {
        $startX = [math]::Floor(($w - $CropWidth) / 2)
        $startY = [math]::Floor(($h - $CropHeight) / 2)
    } else {
        $rand = New-Object System.Random
        $startX = $rand.Next(0, $w - $CropWidth + 1)
        $startY = $rand.Next(0, $h - $CropHeight + 1)
    }
    $out = New-Object 'object[]' $CropHeight
    for ($y = 0; $y -lt $CropHeight; $y++) {
        $row = New-Object 'double[]' $CropWidth
        for ($x = 0; $x -lt $CropWidth; $x++) { $row[$x] = $Image[$startY + $y][$startX + $x] }
        $out[$y] = $row
    }
    return ,$out
}
