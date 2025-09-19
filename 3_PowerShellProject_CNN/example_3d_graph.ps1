# Example: 3D plotting demo using Plot-3DScatter and Plot-Surface
# Requires: matplotlib_ps.ps1

Import-Module "$PSScriptRoot\matplotlib_ps.ps1" -Force

# Create sample 3D scatter data (spiral)
$t = 0..199 | ForEach-Object { $_ / 20.0 }
$x = $t | ForEach-Object { [math]::Cos($_) * $_ }
$y = $t | ForEach-Object { [math]::Sin($_) * $_ }
$z = $t | ForEach-Object { $_ }

$fig = New-Figure -Width 800 -Height 600 -Rows 1 -Cols 2
# Left: 3D scatter (projected as scatter with varying marker size)
Plot-3DScatter -X ($x) -Y ($y) -Z ($z) -Figure $fig -AxisIndex 0 -Label 'Spiral'
Set-Title -Figure $fig -Title '3D Scatter (projected)'

# Right: Surface plot using a generated z = sin(sqrt(x^2+y^2))/r style surface
$gridN = 80
$xs = @(for ($i=0;$i -lt $gridN;$i++) { -4.0 + 8.0 * ($i / ($gridN-1)) })
$ys = $xs
$Z = @()
for ($iy=0; $iy -lt $ys.Count; $iy++) {
    $row = @()
    for ($ix=0; $ix -lt $xs.Count; $ix++) {
        $xx = $xs[$ix]; $yy = $ys[$iy]
        $r = [math]::Sqrt($xx*$xx + $yy*$yy) + 1e-6
        $v = [math]::Sin($r) / $r
        $row += ,[double]$v
    }
    $Z += ,$row
}
Plot-Surface -Z $Z -Figure $fig -AxisIndex 1 -Cmap 'jet'
Set-Title -Figure $fig -Title 'Surface (sinc)' -AxisIndex 1

# Save the figure (will prefer axis bitmaps when available)
$out = Join-Path $PSScriptRoot 'example_3d_graph.png'
Save-Figure -Figure $fig -Path $out
Write-Host "Saved 3D graph to: $out"

# Optionally show (commented out for non-interactive runs)
# Show-Figure -Figure $fig
