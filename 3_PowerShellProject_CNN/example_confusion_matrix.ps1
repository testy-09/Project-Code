# Example: Confusion Matrix Calculation and Plotting
# Requires: model_metrics.ps1, matplotlib_ps.ps1

# Simulated true and predicted labels (3 classes)
$yTrue = @(0, 1, 2, 2, 0, 1, 1, 2, 0, 2)
$yPred = @(0, 2, 1, 2, 0, 0, 1, 2, 0, 1)

Import-Module "$PSScriptRoot\model_metrics.ps1" -Force
Import-Module "$PSScriptRoot\matplotlib_ps.ps1" -Force

# Calculate and display confusion matrix
Show-ConfusionMatrix -TrueLabels $yTrue -PredLabels $yPred -ClassLabels @("Class0","Class1","Class2")
# Also save the generated figure to a PNG for verification
Import-Module "$PSScriptRoot\matplotlib_ps.ps1" -Force
$cm = Get-ConfusionMatrix -Predicted $yPred -Actual $yTrue
$cmDouble = @(); for ($i=0;$i -lt $cm.Count;$i++) { $cmDouble += ,([double[]]$cm[$i]) }
$fig = New-Figure -Width 500 -Height 500 -Rows 1 -Cols 1
Plot-Heatmap -Matrix $cmDouble -Figure $fig -AxisIndex 0 -Annotate -Cmap 'jet' -XLabels @("Class0","Class1","Class2") -YLabels @("Class0","Class1","Class2")
# Prefer saving the axis bitmap directly (more faithful) if present
$outPath = (Join-Path $PSScriptRoot 'confusion_saved.png')
if ($fig.Axes -and $fig.Axes.Count -gt 0 -and $fig.Axes[0].PSObject.Properties['ImageBitmap'] -and $fig.Axes[0].ImageBitmap -ne $null) {
	$fig.Axes[0].ImageBitmap.Save($outPath)
	Write-Host "Saved confusion matrix (axis bitmap) to: $outPath"
} else {
	Save-Figure -Figure $fig -Path $outPath
	Write-Host "Saved confusion matrix (full figure) to: $outPath"
}
