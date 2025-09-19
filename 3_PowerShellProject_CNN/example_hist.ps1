# example_hist.ps1
# Demonstrate histogram plotting using matplotlib_ps.ps1
. "$PSScriptRoot\matplotlib_ps.ps1"

# Generate random data
$rand = New-Object System.Random
$data = @(for ($i=0; $i -lt 1000; $i++) { $rand.NextDouble() * 10 })

$fig = New-Figure -Width 800 -Height 600 -Rows 1 -Cols 1
Plot-Hist -Data $data -Bins 20 -Figure $fig -AxisIndex 0 -Label 'Random Data'
Set-Title -Figure $fig -Title 'Histogram of Random Data'
Set-XLabel -Figure $fig -Label 'Value'
Set-YLabel -Figure $fig -Label 'Frequency'
Show-Figure -Figure $fig
