# Side-by-side + overlay of a Studio viewport capture and a sniper2.mp4 frame (Sniper slice, visual validation).
# (never name a variable $out / $cap here: PowerShell names are case-insensitive and it would overwrite -Out)
# Usage: powershell -File compare.ps1 -Cap <capture.png> -Frame <f####.png of sniper2.mp4 (1280 x 720)> -Out <out.png>
#        [-Label text] [-Grid 1]
# The capture (1452 x 753 viewport) is cropped to 16:9 (same vertical FOV, 70 deg) and scaled to 640 x 360, as is the
# footage frame. Panels: footage | game | 50 % mix (optional 100-px grid of the 1280 x 720 picture on every panel).
param([string]$Cap, [string]$Frame, [string]$Out, [string]$Label = "", [int]$Grid = 0)
Add-Type -AssemblyName System.Drawing
$W = 640; $Hh = 360
$shot = [System.Drawing.Bitmap]::FromFile($Cap)
$cw = [int][math]::Round($shot.Height * 16 / 9)
$cx = [int](($shot.Width - $cw) / 2)
$fr = [System.Drawing.Bitmap]::FromFile($Frame)
$bmp = New-Object System.Drawing.Bitmap ($W * 3 + 8), ($Hh + 22)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($fr, (New-Object System.Drawing.Rectangle 0, 22, $W, $Hh), (New-Object System.Drawing.Rectangle 0, 0, $fr.Width, $fr.Height), [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawImage($shot, (New-Object System.Drawing.Rectangle ($W + 4), 22, $W, $Hh), (New-Object System.Drawing.Rectangle $cx, 0, $cw, $shot.Height), [System.Drawing.GraphicsUnit]::Pixel)
# 50 % mix
$g.DrawImage($fr, (New-Object System.Drawing.Rectangle (2 * $W + 8), 22, $W, $Hh), (New-Object System.Drawing.Rectangle 0, 0, $fr.Width, $fr.Height), [System.Drawing.GraphicsUnit]::Pixel)
$cm = New-Object System.Drawing.Imaging.ColorMatrix
$cm.Matrix33 = 0.5
$ia = New-Object System.Drawing.Imaging.ImageAttributes
$ia.SetColorMatrix($cm)
$g.DrawImage($shot, (New-Object System.Drawing.Rectangle (2 * $W + 8), 22, $W, $Hh), $cx, 0, $cw, $shot.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
if ($Grid -gt 0) {
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(110, 0, 255, 255)), 1
    foreach ($ox in 0, ($W + 4), (2 * $W + 8)) {
        for ($x = 100; $x -lt 1280; $x += 100) { $p = $ox + $x / 2; $g.DrawLine($pen, $p, 22, $p, 22 + $Hh) }
        for ($y = 100; $y -lt 720; $y += 100) { $p = 22 + $y / 2; $g.DrawLine($pen, $ox, $p, $ox + $W, $p) }
    }
}
$font = New-Object System.Drawing.Font 'Arial', 11, ([System.Drawing.FontStyle]::Bold)
$g.DrawString("footage  $([IO.Path]::GetFileNameWithoutExtension($Frame))   |   game   |   50 % mix   $Label", $font, [System.Drawing.Brushes]::Yellow, 4, 3)
$g.Dispose(); $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $shot.Dispose(); $fr.Dispose()
"saved $Out"
