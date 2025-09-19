# nnlib.ps1
# PowerShell Neural Network Operations Library

function Invoke-Convolution2D {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input,
        [Parameter(Mandatory)]
        [object[][]]$Kernel
    )
    $inputRows = $Input.Count
    $inputCols = $Input[0].Count
    $kernelRows = $Kernel.Count
    $kernelCols = $Kernel[0].Count
    $outputRows = $inputRows - $kernelRows + 1
    $outputCols = $inputCols - $kernelCols + 1
    # Guard against kernel larger than input (avoid negative sizes)
    if ($outputRows -le 0 -or $outputCols -le 0) {
        Write-Host "[Invoke-Convolution2D] Warning: kernel larger than input (kernel: $kernelRows x $kernelCols, input: $inputRows x $inputCols). Returning 1x1 zero output." -ForegroundColor Yellow
        $out = New-Object 'object[]' 1
        $rowArr = New-Object 'double[]' 1
        $rowArr[0] = 0.0
        $out[0] = $rowArr
        return ,$out
    }
    # Use .NET arrays for inner loops to reduce PowerShell overhead
    $output = New-Object 'object[]' $outputRows
    for ($i = 0; $i -lt $outputRows; $i++) {
        $rowArr = New-Object 'double[]' $outputCols
        for ($j = 0; $j -lt $outputCols; $j++) {
            $sum = 0.0
            for ($m = 0; $m -lt $kernelRows; $m++) {
                $inRow = $Input[$i + $m]
                $kRow = $Kernel[$m]
                for ($n = 0; $n -lt $kernelCols; $n++) {
                    $sum += [double]$inRow[$j + $n] * [double]$kRow[$n]
                }
            }
            $rowArr[$j] = $sum
        }
        $output[$i] = $rowArr
    }
    return ,$output
}

function Invoke-ReLU {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input
    )
    $output = New-Object 'object[]' $Input.Count
    for ($i = 0; $i -lt $Input.Count; $i++) {
        $row = $Input[$i]
        $outRow = New-Object 'double[]' $row.Count
        for ($j = 0; $j -lt $row.Count; $j++) { $outRow[$j] = [math]::Max(0, [double]$row[$j]) }
        $output[$i] = $outRow
    }
    return ,$output
}

function Invoke-Threshold {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input,
        [Parameter(Mandatory)]
        [double]$Threshold
    )
    $output = New-Object 'object[]' $Input.Count
    for ($i = 0; $i -lt $Input.Count; $i++) {
        $row = $Input[$i]
        $outRow = New-Object 'int[]' $row.Count
        for ($j = 0; $j -lt $row.Count; $j++) {
            if ([double]$row[$j] -ge $Threshold) { $outRow[$j] = 1 } else { $outRow[$j] = 0 }
        }
        $output[$i] = $outRow
    }
    return ,$output
}

if ($PSModuleInfo) { Export-ModuleMember -Function Invoke-Convolution2D,Invoke-ReLU,Invoke-Threshold }
# Cross Entropy Loss for binary classification
function Invoke-CrossEntropyLoss {
    param(
        [Parameter(Mandatory)]
        [double[]]$Predicted,  # predicted probabilities (0-1)
        [Parameter(Mandatory)]
        [int[]]$Target         # true labels (0 or 1)
    )
    $epsilon = 1e-12
    $loss = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        $p = [math]::Max($epsilon, [math]::Min(1 - $epsilon, $Predicted[$i]))
        $t = $Target[$i]
        $loss += -($t * [math]::Log($p) + (1 - $t) * [math]::Log(1 - $p))
    }
    return $loss / $Predicted.Count
}

# Focal Loss for binary classification
function Invoke-FocalLoss {
    param(
        [Parameter(Mandatory)]
        [double[]]$Predicted,  # predicted probabilities (0-1)
        [Parameter(Mandatory)]
        [int[]]$Target,        # true labels (0 or 1)
        [double]$Gamma = 2.0,  # focusing parameter
        [double]$Alpha = 0.25  # balance parameter
    )
    $epsilon = 1e-12
    $loss = 0
    for ($i = 0; $i -lt $Predicted.Count; $i++) {
        $p = [math]::Max($epsilon, [math]::Min(1 - $epsilon, $Predicted[$i]))
        $t = $Target[$i]
        if ($t -eq 1) {
            $loss += -$Alpha * [math]::Pow(1 - $p, $Gamma) * [math]::Log($p)
        } else {
            $loss += -(1 - $Alpha) * [math]::Pow($p, $Gamma) * [math]::Log(1 - $p)
        }
    }
    return $loss / $Predicted.Count
}

if ($PSModuleInfo) { Export-ModuleMember -Function Invoke-CrossEntropyLoss,Invoke-FocalLoss }
# Input Layer: Accepts a 2D array (image)
function Invoke-InputLayer {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input
    )
    return $Input
}

# Convolutional Layer: 2D convolution
function Invoke-ConvolutionalLayer {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input,
        [Parameter(Mandatory)]
        [object[][]]$Kernel
    )
    return Invoke-Convolution2D -Input $Input -Kernel $Kernel
}

# Activation Layer: ReLU
function Invoke-ActivationLayer {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input
    )
    return Invoke-ReLU -Input $Input
}

# Pooling Layer: Max Pooling 2x2
function Invoke-PoolingLayer {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input,
        [int]$PoolSize = 2
    )
    $rows = $Input.Count
    $cols = $Input[0].Count
    $outRows = [math]::Floor($rows / $PoolSize)
    $outCols = [math]::Floor($cols / $PoolSize)
    $output = New-Object 'object[]' $outRows
    for ($i = 0; $i -lt $outRows; $i++) {
        $rowArr = New-Object 'double[]' $outCols
        for ($j = 0; $j -lt $outCols; $j++) {
            $max = -1e308
            for ($m = 0; $m -lt $PoolSize; $m++) {
                $inRow = $Input[$i * $PoolSize + $m]
                for ($n = 0; $n -lt $PoolSize; $n++) {
                    $val = [double]$inRow[$j * $PoolSize + $n]
                    if ($val -gt $max) { $max = $val }
                }
            }
            $rowArr[$j] = $max
        }
        $output[$i] = $rowArr
    }
    return ,$output
}

# Flattening Layer: 2D to 1D
function Invoke-FlatteningLayer {
    param(
        [Parameter(Mandatory)]
        [object[][]]$Input
    )
    $flat = @()
    foreach ($row in $Input) {
        foreach ($val in $row) {
            $flat += [double]$val
        }
    }
    return $flat
}

# Fully Connected Layer (with Dropout)
function Invoke-FullyConnectedLayer {
    param(
        [Parameter(Mandatory)]
        [double[]]$Input,
        [Parameter(Mandatory)]
        [double[]]$Weights,
        [double]$Bias = 0,
        [double]$DropoutRate = 0.0
    )
    $output = 0
    for ($i = 0; $i -lt $Input.Count; $i++) {
        # Dropout: randomly drop units (simulate with probability)
        if ($DropoutRate -gt 0) {
            if ((Get-Random) / [int]::MaxValue -lt $DropoutRate) { continue }
        }
        $output += $Input[$i] * $Weights[$i]
    }
    $output += $Bias
    return $output
}

# Output Layer: Sigmoid for binary, Softmax for multi-class
function Invoke-OutputLayer {
    param(
        [Parameter(Mandatory)]
        [double[]]$Input,
        [ValidateSet('sigmoid','softmax')]
        [string]$Type = 'sigmoid'
    )
    if ($Type -eq 'sigmoid') {
        $out = @()
        foreach ($x in $Input) {
            $out += 1 / (1 + [math]::Exp(-$x))
        }
        return $out
    } elseif ($Type -eq 'softmax') {
        $expVals = @()
        foreach ($x in $Input) {
            $expVals += [math]::Exp($x)
        }
        $sumExp = ($expVals | Measure-Object -Sum).Sum
        $out = @()
        foreach ($e in $expVals) {
            $out += $e / $sumExp
        }
        return $out
    }
}

if ($PSModuleInfo) { Export-ModuleMember -Function Invoke-InputLayer,Invoke-ConvolutionalLayer,Invoke-ActivationLayer,Invoke-PoolingLayer,Invoke-FlatteningLayer,Invoke-FullyConnectedLayer,Invoke-OutputLayer }
