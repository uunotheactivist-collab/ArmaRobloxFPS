# Builds a reference-vs-Roblox sheet: per row the footage frame, the Roblox capture mapped to the footage camera,
# and a 50/50 blend of the two.
# Usage: powershell -File make_comparison.ps1 -Spec <spec.txt> -Out <sheet.png> [-Inset "x,y,w,h"]
#   spec.txt: one row per line, "<footage frame>|<roblox capture png>|<label>"
# Mapping: the footage picture is 480 x 432 (rows 199-631 of the extracted 480-wide frames) with vertical FOV 70
# (assumed, as in every fit) and principal point (239, 229). The Roblox viewport capture (any size) has vertical FOV 70 and its
# principal point at the centre, so it is scaled by 432 / height and shifted so its centre lands on (239, 229).
# Pixels outside the capture are black. -Inset adds a 4x enlargement of a footage-picture region (e.g. the HUD label).
param([string]$Spec, [string]$Out, [string]$Inset = "",
      [string]$Frames = 'C:\Users\cat\Documents\RobloxMilitaryFPS\ReferenceAnalysis\AK\Frames\frames')
Add-Type -AssemblyName System.Drawing
$PW = 480; $PH = 432; $CX = 239.0; $CY = 229.0
$rows = New-Object System.Collections.ArrayList
foreach ($line in @(Get-Content $Spec)) {
    if ($line.Trim() -ne '' -and -not $line.StartsWith('#')) { [void]$rows.Add([string[]]($line -split '\|')) }
}
# (PowerShell names are case-insensitive: never name a variable $inset here, it would overwrite -Inset)
$insetRect = $null
if ($Inset) { $v = $Inset -split ','; $insetRect = New-Object System.Drawing.Rectangle ([int]$v[0]), ([int]$v[1]), ([int]$v[2]), ([int]$v[3]) }
$cols = if ($insetRect) { 4 } else { 3 }
$labelH = 22
$sheetW = 3 * $PW + $(if ($insetRect) { $insetRect.Width * 4 } else { 0 }) + 4 * ($cols - 1)
$sheet = New-Object System.Drawing.Bitmap $sheetW, (($PH + $labelH) * $rows.Count)
$g = [System.Drawing.Graphics]::FromImage($sheet); $g.Clear([System.Drawing.Color]::FromArgb(24, 24, 24))
$g.InterpolationMode = 'HighQualityBicubic'
$font = New-Object System.Drawing.Font 'Arial', 11, ([System.Drawing.FontStyle]::Bold)
$i = 0
foreach ($r in $rows) {
    $fn = [int]$r[0]; $cap = $r[1]; $label = $r[2]
    $y = $i * ($PH + $labelH)
    $g.DrawString("footage $fn  |  Roblox  |  50/50 blend   -  $label", $font, [System.Drawing.Brushes]::Yellow, 4, $y + 3)
    $y += $labelH
    # footage picture
    $ref = [System.Drawing.Image]::FromFile(("{0}\ref_{1:D4}.png" -f $Frames, $fn))
    $refPic = New-Object System.Drawing.Bitmap $PW, $PH
    $gr = [System.Drawing.Graphics]::FromImage($refPic)
    $gr.DrawImage($ref, (New-Object System.Drawing.Rectangle 0, 0, $PW, $PH), (New-Object System.Drawing.Rectangle 0, 199, 480, 432), [System.Drawing.GraphicsUnit]::Pixel)
    $gr.Dispose(); $ref.Dispose()
    # Roblox capture mapped to the footage camera
    $rb = [System.Drawing.Image]::FromFile($cap)
    $s = $PH / [double]$rb.Height
    $rbPic = New-Object System.Drawing.Bitmap $PW, $PH
    $gb = [System.Drawing.Graphics]::FromImage($rbPic); $gb.Clear([System.Drawing.Color]::Black); $gb.InterpolationMode = 'HighQualityBicubic'
    $dx = $CX - ($rb.Width / 2.0) * $s; $dy = $CY - ($rb.Height / 2.0) * $s
    $gb.DrawImage($rb, [float]$dx, [float]$dy, [float]($rb.Width * $s), [float]($rb.Height * $s))
    $gb.Dispose(); $rb.Dispose()
    # blend
    $bl = New-Object System.Drawing.Bitmap $PW, $PH
    $gl = [System.Drawing.Graphics]::FromImage($bl); $gl.DrawImage($refPic, 0, 0)
    $cm = New-Object System.Drawing.Imaging.ColorMatrix; $cm.Matrix33 = 0.5
    $ia = New-Object System.Drawing.Imaging.ImageAttributes; $ia.SetColorMatrix($cm)
    $gl.DrawImage($rbPic, (New-Object System.Drawing.Rectangle 0, 0, $PW, $PH), 0, 0, $PW, $PH, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $gl.Dispose()
    $g.DrawImage($refPic, 0, $y); $g.DrawImage($rbPic, $PW + 4, $y); $g.DrawImage($bl, 2 * ($PW + 4), $y)
    if ($insetRect) {
        $x0 = 3 * ($PW + 4)
        $g.InterpolationMode = 'NearestNeighbor'
        $g.DrawImage($refPic, (New-Object System.Drawing.Rectangle $x0, $y, ($insetRect.Width * 4), ($insetRect.Height * 4)), $insetRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawImage($rbPic, (New-Object System.Drawing.Rectangle $x0, ($y + $insetRect.Height * 4 + 6), ($insetRect.Width * 4), ($insetRect.Height * 4)), $insetRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.InterpolationMode = 'HighQualityBicubic'
    }
    $refPic.Dispose(); $rbPic.Dispose(); $bl.Dispose()
    $i++
}
$g.Dispose(); $sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
"saved $Out ($($rows.Count) rows)"
