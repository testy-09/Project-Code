Import-Module "$PSScriptRoot\data_processing.ps1" -Force
$vals = @('red','blue','green','red','green')
$res = Convert-ToNominalEncoding -Values $vals
Write-Host 'Mapping:'
foreach ($kv in $res.Mapping.GetEnumerator()) { Write-Host "$($kv.Name) -> $($kv.Value)" }
Write-Host 'Encoded: ' + ($res.Encoded -join ',')
$oh = Convert-ToOneHot -Values $vals
Write-Host 'OneHot rows: ' + $oh.OneHot.Count
Write-Host 'OneHot first row: ' + ($oh.OneHot[0] -join ',')
