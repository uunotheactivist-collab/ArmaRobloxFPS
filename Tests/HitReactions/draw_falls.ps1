# Side-view stick figures of sampled falls. Each input line: "t|seg;seg;..." with 13 segments "f1,y1,f2,y2"
# (forward, height in studs) in the order Head, UpperTorso, LowerTorso, RUpperArm, RLowerArm, LUpperArm, LLowerArm,
# RUpperLeg, RLowerLeg, RFoot, LUpperLeg, LLowerLeg, LFoot.
# Usage: draw_falls.ps1 -Out sheet.png -Rows "label=file.txt" ...   (one row per file)
param([string]$Out, [string[]]$Rows, [int]$Cell = 150, [double]$Scale = 26, [double]$FOffset = 1.5)
Add-Type -AssemblyName System.Drawing
$rowData = @()
$maxCols = 0
foreach ($r in $Rows) {
  $label, $file = $r -split '=', 2
  $lines = Get-Content $file | Where-Object { $_.Trim() -ne '' }
  $rowData += ,@($label, $lines)
  if ($lines.Count -gt $maxCols) { $maxCols = $lines.Count }
}
$labelW = 120
$W = $labelW + $maxCols * $Cell; $H = $rowData.Count * ($Cell + 20)
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::FromArgb(250, 250, 248))
$font = New-Object System.Drawing.Font "Arial", 9
$bold = New-Object System.Drawing.Font "Arial", 10, ([System.Drawing.FontStyle]::Bold)
$colors = @('Black','Olive','Olive','Gray','Gray','Silver','Silver','Navy','Navy','Navy','SteelBlue','SteelBlue','SteelBlue')
$widths = @(9, 10, 10, 6, 5, 6, 5, 7, 6, 4, 7, 6, 4)
$order = @(5, 6, 10, 11, 12, 2, 1, 0, 7, 8, 9, 3, 4)  # far side first (left limbs), then body, then near side
for ($ri = 0; $ri -lt $rowData.Count; $ri++) {
  $label = $rowData[$ri][0]; $lines = $rowData[$ri][1]
  $y0 = $ri * ($Cell + 20)
  $g.DrawString($label, $bold, [System.Drawing.Brushes]::Black, 4, $y0 + $Cell / 2 - 8)
  for ($ci = 0; $ci -lt $lines.Count; $ci++) {
    $x0 = $labelW + $ci * $Cell
    $t, $segText = $lines[$ci] -split '\|', 2
    $ground = $y0 + $Cell - 14
    $g.DrawRectangle([System.Drawing.Pens]::Gainsboro, $x0, $y0, $Cell - 2, $Cell)
    $g.DrawLine([System.Drawing.Pens]::DarkGray, $x0 + 2, $ground, $x0 + $Cell - 4, $ground)
    $g.DrawString("t = $t s", $font, [System.Drawing.Brushes]::DimGray, $x0 + 3, $y0 + 2)
    $segs = $segText -split ';'
    foreach ($k in $order) {
      if ($k -ge $segs.Count) { continue }
      $v = $segs[$k] -split ',' | ForEach-Object { [double]$_ }
      $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromName($colors[$k])), $widths[$k]
      $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
      $ax = $x0 + ($v[0] + $FOffset) * $Scale; $ay = $ground - $v[1] * $Scale
      $bx = $x0 + ($v[2] + $FOffset) * $Scale; $by = $ground - $v[3] * $Scale
      $g.DrawLine($pen, [float]$ax, [float]$ay, [float]$bx, [float]$by)
      $pen.Dispose()
    }
  }
}
$g.DrawString("side view, forward = right; ground line = y 0; navy = near leg, steel = far leg, olive = torso, black = head", $font, [System.Drawing.Brushes]::DimGray, 4, $H - 14)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"saved $Out ($W x $H)"
