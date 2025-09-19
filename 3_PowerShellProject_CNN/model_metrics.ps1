# Compute confusion matrix for binary or multiclass classification
function Get-ConfusionMatrix {
    param(
        [int[]]$Predicted,
        [int[]]$Actual,
        [object[]]$Labels = $null
    )
    if ($Predicted.Count -ne $Actual.Count) { throw "Predicted and Actual arrays must be the same length" }
    if ($Labels -eq $null) { $Labels = ($Actual + $Predicted | Sort-Object | Get-Unique) }
    $n = $Labels.Count
    $mat = New-Object 'object[]' $n
    for ($i=0;$i -lt $n;$i++) { $mat[$i] = (New-Object 'int[]' $n) }
    for ($k=0;$k -lt $Predicted.Count;$k++) {
        $a = [array]::IndexOf($Labels, $Actual[$k])
        $p = [array]::IndexOf($Labels, $Predicted[$k])
        if ($a -ge 0 -and $p -ge 0) { $mat[$a][$p]++ }
    }
    return ,$mat
}

# Display confusion matrix as heatmap using matplotlib_ps.ps1
function Show-ConfusionMatrix {
    param(
        [Alias('PredLabels')][int[]]$Predicted,
        [Alias('TrueLabels')][int[]]$Actual,
        [Alias('ClassLabels')][string[]]$Labels = $null,
        [string]$Title = 'Confusion Matrix'
    )
    # Ensure plotting functions are available (dot-source module in same directory)
    . "$PSScriptRoot\matplotlib_ps.ps1"
    # If user provided string display labels, don't pass them to Get-ConfusionMatrix (which expects label values matching Actual/Predicted)
    if ($Labels -ne $null) {
        $displayLabels = $Labels
        $cm = Get-ConfusionMatrix -Predicted $Predicted -Actual $Actual
    } else {
        $cm = Get-ConfusionMatrix -Predicted $Predicted -Actual $Actual
        $displayLabels = ($Actual + $Predicted | Sort-Object | Get-Unique)
    }
    # Convert to double[][] to ensure Plot-Heatmap receives numeric types
    $cmDouble = @()
    for ($i = 0; $i -lt $cm.Count; $i++) { $cmDouble += ,([double[]]$cm[$i]) }
    Write-Host "DEBUG: Confusion matrix dims = $($cmDouble.Count) x $($cmDouble[0].Count)"
    for ($r=0; $r -lt $cmDouble.Count; $r++) { Write-Host ("ROW {0}`t{1}" -f $r, ($cmDouble[$r] -join ',')) }
    $fig = New-Figure -Width 500 -Height 500 -Rows 1 -Cols 1
    Plot-Heatmap -Matrix $cmDouble -Figure $fig -AxisIndex 0 -Cmap 'jet' -XLabels $displayLabels -YLabels $displayLabels -Annotate
    Set-Title -Figure $fig -Title $Title
    Show-Figure -Figure $fig
}
# model_metrics.ps1
# Machine learning evaluation metrics implemented in PowerShell

function Get-Accuracy {
    param(
        [Parameter(Mandatory)]
        [int[]]$Predicted, # predicted labels 0/1
        [Parameter(Mandatory)]
        [int[]]$Actual     # true labels 0/1
    )
    if ($Predicted.Count -ne $Actual.Count) { throw "Predicted and Actual arrays must be the same length" }
    if ($Predicted.Count -eq 0) { return 0 }
    $correct = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        if ($Predicted[$i] -eq $Actual[$i]) { $correct++ }
    }
    return $correct / $Predicted.Count
}

function Get-Precision {
    param(
        [int[]]$Predicted,
        [int[]]$Actual
    )
    if ($Predicted.Count -ne $Actual.Count) { throw "Predicted and Actual arrays must be the same length" }
    $tp = 0; $fp = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        if ($Predicted[$i] -eq 1 -and $Actual[$i] -eq 1) { $tp++ }
        if ($Predicted[$i] -eq 1 -and $Actual[$i] -eq 0) { $fp++ }
    }
    if ($tp + $fp -eq 0) { return 0 }
    return $tp / ($tp + $fp)
}

function Get-Recall {
    param(
        [int[]]$Predicted,
        [int[]]$Actual
    )
    if ($Predicted.Count -ne $Actual.Count) { throw "Predicted and Actual arrays must be the same length" }
    $tp = 0; $fn = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        if ($Predicted[$i] -eq 1 -and $Actual[$i] -eq 1) { $tp++ }
        if ($Predicted[$i] -eq 0 -and $Actual[$i] -eq 1) { $fn++ }
    }
    if ($tp + $fn -eq 0) { return 0 }
    return $tp / ($tp + $fn)
}

function Get-F1Score {
    param(
        [int[]]$Predicted,
        [int[]]$Actual
    )
    $prec = Get-Precision -Predicted $Predicted -Actual $Actual
    $rec = Get-Recall -Predicted $Predicted -Actual $Actual
    if ($prec + $rec -eq 0) { return 0 }
    return 2 * ($prec * $rec) / ($prec + $rec)
}

# ROC and AUC assume predicted probabilities (0..1) and binary actual labels (0/1)
function Get-ROC {
    param(
        [double[]]$Scores, # predicted probabilities
        [int[]]$Actual
    )
    if ($Scores.Count -ne $Actual.Count) { throw "Scores and Actual arrays must be the same length" }
    $pairs = for ($i = 0; $i -lt $Scores.Count; $i++) { [PSCustomObject]@{Score=$Scores[$i]; Label=$Actual[$i]} }
    # sort by descending score
    $sorted = $pairs | Sort-Object -Property Score -Descending
    $pos = ($Actual | Where-Object { $_ -eq 1 }).Count
    $neg = $Actual.Count - $pos
    if ($pos -eq 0 -or $neg -eq 0) {
        throw "ROC requires both positive and negative examples"
    }
    $tprList = @(); $fprList = @();
    $tp = 0; $fp = 0
    $prevScore = [double]::NegativeInfinity
    foreach ($item in $sorted) {
        if ($item.Score -ne $prevScore) {
            $tprList += ($tp / $pos)
            $fprList += ($fp / $neg)
            $prevScore = $item.Score
        }
        if ($item.Label -eq 1) { $tp++ } else { $fp++ }
    }
    # final point
    $tprList += ($tp / $pos)
    $fprList += ($fp / $neg)
    return [PSCustomObject]@{TPR=$tprList; FPR=$fprList}
 }
 
 function Get-AUC {
     param(
         [double[]]$Scores,
         [int[]]$Actual
     )
     $roc = Get-ROC -Scores $Scores -Actual $Actual
     $tpr = $roc.TPR
     $fpr = $roc.FPR
     # trapezoidal rule
     $auc = 0.0
     for ($i = 1; $i -lt $tpr.Count; $i++) {
         $dx = $fpr[$i] - $fpr[$i - 1]
         $avgY = ($tpr[$i] + $tpr[$i - 1]) / 2
         $auc += $dx * $avgY
     }
     return $auc
 }
 
if ($PSModuleInfo) { Export-ModuleMember -Function Get-Accuracy,Get-Precision,Get-Recall,Get-F1Score,Get-ROC,Get-AUC,Get-ConfusionMatrix,Show-ConfusionMatrix }
