# Example: Correlation Matrix Calculation and Plotting
# Requires: data_processing.ps1, matplotlib_ps.ps1

# Generate a sample dataset (5 samples, 3 features)
$data = @(
    @(1, 2, 3),
    @(2, 4, 6),
    @(3, 6, 9),
    @(4, 8, 12),
    @(5, 10, 15)
)

# Calculate correlation matrix
Import-Module "$PSScriptRoot\data_processing.ps1" -Force
Import-Module "$PSScriptRoot\matplotlib_ps.ps1" -Force

$corMat = Get-CorrelationMatrix -Data $data

# Plot correlation matrix as heatmap
Plot-Heatmap -Matrix $corMat -Title "Correlation Matrix" -XLabels @("F1","F2","F3") -YLabels @("F1","F2","F3")
