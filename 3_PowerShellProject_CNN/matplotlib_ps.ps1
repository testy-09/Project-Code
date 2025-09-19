# Plot a heatmap (matrix) with optional value annotations
function Plot-Heatmap {
    param(
        [double[][]]$Matrix,
        $Figure,
        [int]$AxisIndex=0,
        [string]$Cmap='jet',
        [string[]]$XLabels=$null,
        [string[]]$YLabels=$null,
        [string[]]$RowColors=$null,
        [switch]$Annotate
    )
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    $rows = $Matrix.Count; $cols = $Matrix[0].Count
    # use a larger per-cell size so annotations and cells are visible
    $cellSize = 60
    $pixelFormat = [int][System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    $bmp = New-Object System.Drawing.Bitmap ($cols * $cellSize), ($rows * $cellSize), $pixelFormat
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::White)
    $min = [double]::PositiveInfinity; $max = [double]::NegativeInfinity
    for ($y=0;$y -lt $rows;$y++) { for ($x=0;$x -lt $cols;$x++) { $v = [double]$Matrix[$y][$x]; if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } } }
    $range = $max - $min; if ($range -eq 0) { $range = 1 }
    # prepare row base colors
    if ($RowColors -eq $null) {
        $preset = @('Red','Green','Blue','Orange','Purple','Teal','Brown','Pink','Yellow','Gray')
        $rowColorObjs = for ($i=0; $i -lt $rows; $i++) { [System.Drawing.Color]::FromName($preset[$i % $preset.Count]) }
    } else {
        $rowColorObjs = for ($i=0; $i -lt $rows; $i++) { [System.Drawing.Color]::FromName($RowColors[$i % $RowColors.Count]) }
    }
    for ($y=0;$y -lt $rows;$y++) {
        for ($x=0;$x -lt $cols;$x++) {
            $v = ([double]$Matrix[$y][$x] - $min) / $range
            # blend base row color with white according to value (v)
            $base = $rowColorObjs[$y]
            $r = [int]([math]::Round((1 - $v) * 255 + $v * $base.R))
            $gcol = [int]([math]::Round((1 - $v) * 255 + $v * $base.G))
            $b = [int]([math]::Round((1 - $v) * 255 + $v * $base.B))
            $fillColor = [System.Drawing.Color]::FromArgb($r,$gcol,$b)
            $brush = New-Object System.Drawing.SolidBrush $fillColor
            $rect = [System.Drawing.Rectangle]::new($x * $cellSize, $y * $cellSize, $cellSize, $cellSize)
            $g.FillRectangle($brush, $rect)
            # draw border
            $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(180,0,0,0), 1)
            $g.DrawRectangle($pen, $rect)
            $pen.Dispose()
            $brush.Dispose()
        }
    }
    # Replace chart with PictureBox if needed
    if ($ctrl -is [System.Windows.Forms.PictureBox]) {
        $ctrl.Image = $bmp
        # always attach the bitmap to the axis object so Save-Figure can find it
        $Figure.Axes[$AxisIndex] | Add-Member -NotePropertyName ImageBitmap -NotePropertyValue $bmp -Force
        $ctrl.Refresh()
    } else {
        $parent = $ctrl.Parent
        # determine row/col for this axis
        $row = [math]::Floor($AxisIndex / $Figure.Cols)
        $col = $AxisIndex % $Figure.Cols
        $parent.Controls.Remove($ctrl)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Dock = 'Fill'
        $pb.SizeMode = 'Zoom'
        $pb.Image = $bmp
        # add to the same cell in the table layout
        $parent.Controls.Add($pb, $col, $row)
        $Figure.Axes[$AxisIndex].Control = $pb
        $Figure.Axes[$AxisIndex].Type = 'image'
        # ensure axis has ImageBitmap regardless of branch
        $Figure.Axes[$AxisIndex] | Add-Member -NotePropertyName ImageBitmap -NotePropertyValue $bmp -Force
        $pb.Refresh()
    }
    # Optionally annotate values
    if ($Annotate) {
        # choose font size proportional to cell size for readability
    $fontSize = [math]::Max(10, [math]::Round($cellSize * 0.42))
    # use explicit constructor to avoid ambiguous overloads (specify GraphicsUnit)
    $font = [System.Drawing.Font]::new('Arial', [float]$fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        for ($y=0;$y -lt $rows;$y++) {
            for ($x=0;$x -lt $cols;$x++) {
                $val = [math]::Round($Matrix[$y][$x],2)
                $str = $val.ToString()
                $rectf = [System.Drawing.RectangleF]::new($x * $cellSize, $y * $cellSize, $cellSize, $cellSize)
                $v = ([double]$Matrix[$y][$x] - $min) / $range
                # compute luminance from the actual fill color used for this cell so text contrasts correctly
                $base = $rowColorObjs[$y]
                $rC = [int]([math]::Round((1 - $v) * 255 + $v * $base.R))
                $gC = [int]([math]::Round((1 - $v) * 255 + $v * $base.G))
                $bC = [int]([math]::Round((1 - $v) * 255 + $v * $base.B))
                $fillColor = [System.Drawing.Color]::FromArgb($rC,$gC,$bC)
                $luma = (0.299 * $fillColor.R + 0.587 * $fillColor.G + 0.114 * $fillColor.B) / 255.0
                if ($luma -lt 0.5) { $textColor = [System.Drawing.Color]::FromArgb(255,255,255); $outlineColor = [System.Drawing.Color]::FromArgb(0,0,0) } else { $textColor = [System.Drawing.Color]::FromArgb(0,0,0); $outlineColor = [System.Drawing.Color]::FromArgb(255,255,255) }
                $textBrush = New-Object System.Drawing.SolidBrush $textColor
                $outlineBrush = New-Object System.Drawing.SolidBrush $outlineColor
                # draw a simple outline by drawing the string slightly offset in four directions using outline color
                $offsets = @( [System.Drawing.PointF]::new(-1,-1), [System.Drawing.PointF]::new(-1,1), [System.Drawing.PointF]::new(1,-1), [System.Drawing.PointF]::new(1,1) )
                foreach ($ofs in $offsets) {
                    $rectOff = [System.Drawing.RectangleF]::new($rectf.X + $ofs.X, $rectf.Y + $ofs.Y, $rectf.Width, $rectf.Height)
                    $g.DrawString($str, $font, $outlineBrush, $rectOff, $sf)
                }
                # main text
                $g.DrawString($str, $font, $textBrush, $rectf, $sf)
                $textBrush.Dispose(); $outlineBrush.Dispose()
            }
        }
        if ($font) { $font.Dispose() }
    }
    $g.Dispose()
    # Optionally add axis labels (not shown on image, but can be added to form title)
    if ($XLabels -ne $null) { $Figure.Form.Text += " | X: " + ($XLabels -join ',') }
    if ($YLabels -ne $null) { $Figure.Form.Text += " | Y: " + ($YLabels -join ',') }
    return $Figure
}
# matplotlib_ps.ps1
# Lightweight plotting utilities inspired by Python's matplotlib using .NET

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Windows.Forms.DataVisualization
Add-Type -AssemblyName System.Drawing

# Create a Figure that can contain a grid of axes (subplots). Each axis is either a Chart or PictureBox.
function New-Figure {
    param([int]$Width = 800, [int]$Height = 600, [int]$Rows = 1, [int]$Cols = 1)
    Write-Host "DEBUG: Rows=$Rows (type $($Rows.GetType().FullName)), Cols=$Cols (type $($Cols.GetType().FullName))"
    $nRows = [int]($Rows | Select-Object -First 1)
    $nCols = [int]($Cols | Select-Object -First 1)
    $form = New-Object System.Windows.Forms.Form
    $form.Width = $Width; $form.Height = $Height
    $table = New-Object System.Windows.Forms.TableLayoutPanel
    $table.Dock = 'Fill'
    $table.RowCount = $nRows; $table.ColumnCount = $nCols
    for ($r=0;$r -lt $nRows;$r++) { $table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', [float](100.0/$nRows)))) }
    for ($c=0;$c -lt $nCols;$c++) { $table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', [float](100.0/$nCols)))) }
    $axes = @()
    for ($r=0;$r -lt $nRows;$r++) {
        for ($c=0;$c -lt $nCols;$c++) {
            $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
            $chart.Dock = 'Fill'
            $ca = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "A$r$c"
            $chart.ChartAreas.Add($ca)
            $table.Controls.Add($chart, $c, $r)
            $axes += [PSCustomObject]@{Control=$chart; Type='chart'; ChartArea=$ca}
        }
    }
    $form.Controls.Add($table)
    return [PSCustomObject]@{Form=$form; Grid=$table; Axes=$axes; Rows=$nRows; Cols=$nCols}
}

function Get-AxisControl {
    param($Figure, [int]$AxisIndex = 0)
    return $Figure.Axes[$AxisIndex].Control
}

function Plot-Line {
    param([double[]]$X, [double[]]$Y, $Figure, [int]$AxisIndex = 0, [string]$Label = 'Series')
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) {
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Label
        $series.ChartType = 'Line'
        $series.ChartArea = $Figure.Axes[$AxisIndex].ChartArea.Name
        for ($i=0;$i -lt $X.Count;$i++) { $series.Points.AddXY($X[$i], $Y[$i]) }
        $ctrl.Series.Add($series)
    } else {
        # replace PictureBox with Chart
        $parent = $ctrl.Parent
        $pos = $parent.GetRow($ctrl), $parent.GetColumn($ctrl)
        $parent.Controls.Remove($ctrl)
        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Dock = 'Fill'
        $ca = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "A$AxisIndex"
        $chart.ChartAreas.Add($ca)
        $parent.Controls.Add($chart)
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Label
        $series.ChartType = 'Line'
        for ($i=0;$i -lt $X.Count;$i++) { $series.Points.AddXY($X[$i], $Y[$i]) }
        $chart.Series.Add($series)
        $Figure.Axes[$AxisIndex].Control = $chart
        $Figure.Axes[$AxisIndex].Type = 'chart'
        $Figure.Axes[$AxisIndex].ChartArea = $ca
    }
    return $Figure
}

function Plot-Scatter {
    param([double[]]$X,[double[]]$Y,$Figure,[int]$AxisIndex = 0,[string]$Label='Series')
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) {
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Label
        $series.ChartType = 'Point'
        $series.ChartArea = $Figure.Axes[$AxisIndex].ChartArea.Name
        for ($i = 0; $i -lt $X.Count; $i++) { $series.Points.AddXY($X[$i], $Y[$i]) }
        $ctrl.Series.Add($series)
    } else { Plot-Line -X $X -Y $Y -Figure $Figure -AxisIndex $AxisIndex -Label $Label }
    return $Figure
}

# Very small 3D helpers: approximate 3D scatter by projecting Z into marker size and color
function Plot-3DScatter {
    param([double[]]$X, [double[]]$Y, [double[]]$Z, $Figure, [int]$AxisIndex = 0, [string]$Label='3D')
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    # Use scatter with varying point size to simulate depth
    $sizes = $Z | ForEach-Object { [math]::Max(2, [math]::Round(($_ + 1) * 5)) }
    if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) {
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Label
        $series.ChartType = 'Point'
        $series.ChartArea = $Figure.Axes[$AxisIndex].ChartArea.Name
        for ($i=0;$i -lt $X.Count;$i++) { $pt = $series.Points.AddXY($X[$i], $Y[$i]); $series.Points[$pt].MarkerSize = $sizes[$i] }
        $ctrl.Series.Add($series)
    } else { Plot-Scatter -X $X -Y $Y -Figure $Figure -AxisIndex $AxisIndex -Label $Label }
    return $Figure
}

# Surface plot: accept grid X,Y and matrix Z; render as image
function Plot-Surface {
    param([double[][]]$Z, $Figure, [int]$AxisIndex = 0, [string]$Cmap='jet')
    if ($Figure -eq $null) { $Figure = New-Figure }
    # reuse Imshow to render matrix
    Imshow -Matrix $Z -Figure $Figure -AxisIndex $AxisIndex -Cmap $Cmap
    return $Figure
}

function Plot-Hist {
    param([double[]]$Data,[int]$Bins = 10,$Figure,[int]$AxisIndex = 0,[string]$Label='Hist')
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    $min = ($Data | Measure-Object -Minimum).Minimum; $max = ($Data | Measure-Object -Maximum).Maximum
    $binWidth = ($max - $min) / $Bins
    $counts = @(for ($i=0;$i -lt $Bins;$i++) { 0 })
    foreach ($v in $Data) { $idx = [math]::Min([math]::Floor((($v - $min) / ($max - $min)) * $Bins), $Bins - 1); $counts[$idx]++ }
    $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $Label
    $series.ChartType = 'Column'
    $series.ChartArea = $Figure.Axes[$AxisIndex].ChartArea.Name
    for ($i=0;$i -lt $Bins;$i++) { $x = $min + ($i + 0.5) * $binWidth; $series.Points.AddXY($x, $counts[$i]) }
    $ctrl.Series.Add($series)
    return $Figure
}

function Set-Title { param($Figure, [string]$Title, [int]$AxisIndex=0) if ($Figure -ne $null) { $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex; if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) { $ctrl.Titles.Clear(); $ctrl.Titles.Add($Title) } else { $Figure.Form.Text = $Title } } }

function Set-XLabel { param($Figure, [string]$Label, [int]$AxisIndex=0) if ($Figure -ne $null) { $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex; if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) { $ctrl.ChartAreas[$Figure.Axes[$AxisIndex].ChartArea.Name].AxisX.Title = $Label } } }

function Set-YLabel { param($Figure, [string]$Label, [int]$AxisIndex=0) if ($Figure -ne $null) { $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex; if ($ctrl -is [System.Windows.Forms.DataVisualization.Charting.Chart]) { $ctrl.ChartAreas[$Figure.Axes[$AxisIndex].ChartArea.Name].AxisY.Title = $Label } } }

function Add-Legend { param($Figure, [string]$Position='Top') if ($Figure -ne $null) { $chart = Get-AxisControl -Figure $Figure -AxisIndex 0; if ($chart -is [System.Windows.Forms.DataVisualization.Charting.Chart]) { $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend 'L'; $legend.Docking = $Position; $chart.Legends.Add($legend) } } }

# simple colormap functions
function Get-ColormapColor {
    param([double]$v, [string]$cmap='gray')
    $vv = [math]::Max(0.0, [math]::Min(1.0, $v))
    switch ($cmap) {
        'gray' { $g = [int]([math]::Round(255 * $vv)); return [System.Drawing.Color]::FromArgb($g,$g,$g) }
        'jet' {
            # approximate jet
            $r = [int]([math]::Round(255 * [math]::Max(0, [math]::Min(1, 1.5 - [math]::Abs(4*$vv - 3)))))
            $g = [int]([math]::Round(255 * [math]::Max(0, [math]::Min(1, 1.5 - [math]::Abs(4*$vv - 2)))))
            $b = [int]([math]::Round(255 * [math]::Max(0, [math]::Min(1, 1.5 - [math]::Abs(4*$vv - 1)))))
            return [System.Drawing.Color]::FromArgb($r,$g,$b)
        }
        default { $g = [int]([math]::Round(255 * $vv)); return [System.Drawing.Color]::FromArgb($g,$g,$g) }
    }
}

function Imshow {
    param([double[][]]$Matrix, $Figure, [int]$AxisIndex=0, [string]$Cmap='gray')
    if ($Figure -eq $null) { $Figure = New-Figure }
    $ctrl = Get-AxisControl -Figure $Figure -AxisIndex $AxisIndex
    $rows = $Matrix.Count; $cols = $Matrix[0].Count
    $pixelFormat = [int][System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    $bmp = New-Object System.Drawing.Bitmap $cols, $rows, $pixelFormat
    # normalize matrix to 0..1
    $min = [double]::PositiveInfinity; $max = [double]::NegativeInfinity
    for ($y=0;$y -lt $rows;$y++) { for ($x=0;$x -lt $cols;$x++) { $v = [double]$Matrix[$y][$x]; if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } } }
    $range = $max - $min; if ($range -eq 0) { $range = 1 }
    for ($y=0;$y -lt $rows;$y++) {
        for ($x=0;$x -lt $cols;$x++) {
            $v = ([double]$Matrix[$y][$x] - $min) / $range
            $c = Get-ColormapColor -v $v -cmap $Cmap
            $bmp.SetPixel($x,$y,$c)
        }
    }
    if ($ctrl -is [System.Windows.Forms.PictureBox]) {
        $ctrl.Image = $bmp
        $ctrl.Refresh()
    } else {
        $parent = $ctrl.Parent
        $row = [math]::Floor($AxisIndex / $Figure.Cols)
        $col = $AxisIndex % $Figure.Cols
        $parent.Controls.Remove($ctrl)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Dock = 'Fill'
        $pb.SizeMode = 'Zoom'
        $pb.Image = $bmp
        $parent.Controls.Add($pb, $col, $row)
    $Figure.Axes[$AxisIndex].Control = $pb
    $Figure.Axes[$AxisIndex].Type = 'image'
    $Figure.Axes[$AxisIndex] | Add-Member -NotePropertyName ImageBitmap -NotePropertyValue $bmp -Force
        $pb.Refresh()
    }
    # ensure the form repaints
    if ($Figure.Form -ne $null) { $Figure.Form.Refresh() }
    return $Figure
}

function Save-Figure {
    param($Figure, [string]$Path)
    # Check each axis for an attached ImageBitmap or PictureBox.Image and save the first found
    if ($Figure -and $Figure.Axes -and $Figure.Axes.Count -gt 0) {
        foreach ($ax in $Figure.Axes) {
            if ($ax.PSObject.Properties['ImageBitmap'] -and $ax.ImageBitmap -ne $null) {
                $ax.ImageBitmap.Save($Path)
                return
            }
            try {
                if ($ax.Control -and $ax.Control.GetType().Name -eq 'PictureBox' -and $ax.Control.Image -ne $null) {
                    $ax.Control.Image.Save($Path)
                    return
                }
            } catch { }
        }
    }
    # Fallback: render the whole form
    $bmp = New-Object System.Drawing.Bitmap $Figure.Form.Width, $Figure.Form.Height
    $Figure.Form.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0,0,$Figure.Form.Width,$Figure.Form.Height))
    $bmp.Save($Path)
    $bmp.Dispose()
}

function Show-Figure {
    param($Figure)
    $form = $Figure.Form
    $form.StartPosition = 'CenterScreen'
    $form.Add_Shown({ param($s,$e) $s.Activate() })
    [void]$form.ShowDialog()
}

function Close-Figure { param($Figure) if ($Figure -ne $null) { $Figure.Form.Close() } }

function Clear-Figure { param($Figure) if ($Figure -ne $null) { $Figure.Grid.Controls.Clear(); $Figure.Axes = @() } }

if ($PSModuleInfo) { Export-ModuleMember -Function New-Figure,Plot-Line,Plot-Scatter,Plot-Hist,Set-Title,Set-XLabel,Set-YLabel,Add-Legend,Imshow,Save-Figure,Show-Figure,Close-Figure,Clear-Figure,Get-AxisControl,Get-ColormapColor,Plot-Heatmap }
