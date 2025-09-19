# cnn2d.ps1
# Implements a basic 2D convolution operation in PowerShell
function Invoke-CNN2D {
    param(
        [Parameter(Mandatory)]
        [array]$InputArray,
        [Parameter(Mandatory)]
        [array]$KernelArray
    )
    try {
        Write-Host "[Invoke-CNN2D] input rows: $($InputArray.Count); kernel rows: $($KernelArray.Count)"
        if ($InputArray.Count -eq 0 -or $KernelArray.Count -eq 0) {
            throw "Input and Kernel must be non-empty arrays"
        }
        $inputRows = $InputArray.Count
        $inputCols = ($InputArray[0] -as [array]).Count
        $kernelRows = $KernelArray.Count
        $kernelCols = ($KernelArray[0] -as [array]).Count
        $outputRows = $inputRows - $kernelRows + 1
        $outputCols = $inputCols - $kernelCols + 1
        if ($outputRows -le 0 -or $outputCols -le 0) {
            throw "Kernel larger than input in at least one dimension"
        }
        $output = @()
        for ($i = 0; $i -lt $outputRows; $i++) {
            $row = New-Object System.Collections.ArrayList
            for ($j = 0; $j -lt $outputCols; $j++) {
                $sum = 0.0
                for ($m = 0; $m -lt $kernelRows; $m++) {
                    for ($n = 0; $n -lt $kernelCols; $n++) {
                        $a = [double]($InputArray[$i + $m][$j + $n])
                        $b = [double]($KernelArray[$m][$n])
                        $sum += $a * $b
                    }
                }
                [void]$row.Add($sum)
            }
            # convert row to a simple array before adding
            $output += ,($row.ToArray())
        }
        Write-Host "[Invoke-CNN2D] produced output dims: $($output.Count) x $($output[0].Count)"
        return ,$output
    } catch {
        Write-Host "[Invoke-CNN2D] ERROR: $_" -ForegroundColor Red
        return $null
    }
}

# Compatibility wrapper: some scripts call Invoke-Convolution2D
function Invoke-Convolution2D {
    param(
        [Parameter(Mandatory)][array]$Input,
        [Parameter(Mandatory)][array]$Kernel
    )
    return Invoke-CNN2D -InputArray $Input -KernelArray $Kernel
}