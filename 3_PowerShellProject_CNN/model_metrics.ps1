function Get-F1Score {
    param(
        [Parameter(Mandatory)][int[]]$Predicted,
        [Parameter(Mandatory)][int[]]$Actual,
        [int]$PositiveLabel = 1
    )
    if ($Predicted.Count -ne $Actual.Count) { throw 'Predicted and Actual must be same length' }
    $tp = 0; $fp = 0; $fn = 0
    for ($i=0;$i -lt $Predicted.Count;$i++) {
        $p = $Predicted[$i]; $a = $Actual[$i]
        if ($p -eq $PositiveLabel -and $a -eq $PositiveLabel) { $tp++ }
        if ($p -eq $PositiveLabel -and $a -ne $PositiveLabel) { $fp++ }
        if ($p -ne $PositiveLabel -and $a -eq $PositiveLabel) { $fn++ }
    }
    $precision = if (($tp + $fp) -eq 0) { 0.0 } else { $tp / ($tp + $fp) }
    $recall = if (($tp + $fn) -eq 0) { 0.0 } else { $tp / ($tp + $fn) }
    if (($precision + $recall) -eq 0) { return 0.0 }
    $f1 = 2 * $precision * $recall / ($precision + $recall)
    return [math]::Round($f1, 4)
}

if ($PSModuleInfo) { Export-ModuleMember -Function Get-F1Score }
