Import-Module "$PSScriptRoot\matplotlib_ps.ps1" -Force
$fig = New-Figure -Width 500 -Height 500 -Rows 1 -Cols 1
$cm = @(@(3,0,0), @(1,1,1), @(0,2,2))
$fig = Plot-Heatmap -Matrix $cm -Figure $fig -AxisIndex 0 -Annotate -Cmap 'jet'
$ax = $fig.Axes[0]
$hasProp = $ax.PSObject.Properties.Match('ImageBitmap').Count -gt 0
Write-Host "Has ImageBitmap property? $hasProp"
if ($hasProp) { Write-Host "ImageBitmap is null? $([string]($ax.ImageBitmap -eq $null))"; if ($ax.ImageBitmap -ne $null) { $ax.ImageBitmap.Save((Join-Path $PSScriptRoot 'axis_direct_save.png')); Write-Host 'Saved axis_direct_save.png' } }
else { Write-Host 'No ImageBitmap attached to axis.' }

# Also check the PictureBox control if present
if ($ax.Control -and $ax.Control.GetType().Name -eq 'PictureBox') { Write-Host "Axis.Control is PictureBox. PictureBox.Image null? $([string]($ax.Control.Image -eq $null))"; if ($ax.Control.Image -ne $null) { $ax.Control.Image.Save((Join-Path $PSScriptRoot 'picturebox_save.png')); Write-Host 'Saved picturebox_save.png' } }

# Print Axis object properties for debugging
Write-Host "Axis properties:"
$ax | Format-List * -Force

# Save full figure too
Save-Figure -Figure $fig -Path (Join-Path $PSScriptRoot 'fullfigure_save.png')
Write-Host 'Saved fullfigure_save.png'
