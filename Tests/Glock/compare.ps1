# Side-by-side + overlay of a Studio viewport capture and a Glock footage frame (Glock slice, visual validation).
# (never name a variable $out / $cap here: PowerShell names are case-insensitive and it would overwrite -Out)
# Usage: powershell -File compare.ps1 -Cap <capture.png> -Frame <f####.png of glock animation.mp4> -Out <out.png> [-Label text]
# The capture (1452 x 753 viewport) is cropped to the footage's 16:9 picture (same vertical FOV, 70 deg) and scaled to
# 720 x 405; the footage frame's game picture is rows 438-842 of the portrait recording. Panels: footage | game | 50 % mix.
param([string]$Cap, [string]$Frame, [string]$Out, [string]$Label = "")
Add-Type -AssemblyName System.Drawing
$W = 720; $Hh = 405
$shot = [System.Drawing.Bitmap]::FromFile($Cap)
$cw = [int][math]::Round($shot.Height * 16 / 9)
$cx = [int](($shot.Width - $cw) / 2)
$fr = [System.Drawing.Bitmap]::FromFile($Frame)
$sheet = New-Object System.Drawing.Bitmap ($W * 3 + 16), ($Hh + 22)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($fr, (New-Object System.Drawing.Rectangle 0, 22, $W, $Hh), (New-Object System.Drawing.Rectangle 0, 438, 720, 405), [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawImage($shot, (New-Object System.Drawing.Rectangle ($W + 8), 22, $W, $Hh), (New-Object System.Drawing.Rectangle $cx, 0, $cw, $shot.Height), [System.Drawing.GraphicsUnit]::Pixel)
$g.DrawImage($fr, (New-Object System.Drawing.Rectangle (2 * $W + 16), 22, $W, $Hh), (New-Object System.Drawing.Rectangle 0, 438, 720, 405), [System.Drawing.GraphicsUnit]::Pixel)
$cm = New-Object System.Drawing.Imaging.ColorMatrix
$cm.Matrix33 = 0.5
$ia = New-Object System.Drawing.Imaging.ImageAttributes
$ia.SetColorMatrix($cm)
$g.DrawImage($shot, (New-Object System.Drawing.Rectangle (2 * $W + 16), 22, $W, $Hh), $cx, 0, $cw, $shot.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
$font = New-Object System.Drawing.Font "Segoe UI", 11
$g.DrawString("footage $(Split-Path $Frame -Leaf)   |   Roblox   |   50 % overlay   $Label", $font, [System.Drawing.Brushes]::Black, 4, 2)
$g.Dispose()
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose(); $shot.Dispose(); $fr.Dispose()
"saved $Out"
