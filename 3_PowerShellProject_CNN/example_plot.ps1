# example_plot.ps1
# Demonstrate line plotting using matplotlib_ps.ps1
. "$PSScriptRoot\matplotlib_ps.ps1"

$x = 0..99 | ForEach-Object { $_ }
$y = $x | ForEach-Object { [math]::Sin($_ / 10.0) }
$fig = New-Figure -Width 800 -Height 600 -Rows 1 -Cols 1
Plot-Line -X $x -Y $y -Figure $fig -AxisIndex 0 -Label 'sine'
Set-Title -Figure $fig -Title 'Sine Wave'
Set-XLabel -Figure $fig -Label 'x'
Set-YLabel -Figure $fig -Label 'sin(x)'
Show-Figure -Figure $fig
