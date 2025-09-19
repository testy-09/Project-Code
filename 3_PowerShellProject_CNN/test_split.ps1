. "$PSScriptRoot\data_processing.ps1"

# Create synthetic dataset: 20 samples, each sample is a small feature array
$X = for ($i=0; $i -lt 20; $i++) { ,(1..5) }
$y = for ($i=0; $i -lt 20; $i++) { $i % 2 }

$res = Split-TrainTest -X $X -y $y -TestSize 0.2 -Seed 1
Write-Host "No SampleSize => Train:$($res.X_train.Count) Test:$($res.X_test.Count)"

$res2 = Split-TrainTest -X $X -y $y -TestSize 0.2 -Seed 1 -SampleSize 10
Write-Host "SampleSize=10 => Train:$($res2.X_train.Count) Test:$($res2.X_test.Count)"

$res3 = Split-TrainTest -X $X -y $y -TestSize 0.2 -Seed 1 -SampleSize 10 -Stratify
Write-Host "Stratify SampleSize=10 => Train:$($res3.X_train.Count) Test:$($res3.X_test.Count)"

# Show sample class distribution for the sampled set (approx)
function Show-Counts($arr) { $h=@{}; foreach ($v in $arr) { if (-not $h.ContainsKey($v)) { $h[$v]=0 }; $h[$v]++ }; return $h }

# For demonstration, show label distribution across train/test for stratified sample
Write-Host "Stratified sample label distribution (train):"; Show-Counts $res3.y_train | ForEach-Object { Write-Host "$_" }
Write-Host "Stratified sample label distribution (test):"; Show-Counts $res3.y_test | ForEach-Object { Write-Host "$_" }
