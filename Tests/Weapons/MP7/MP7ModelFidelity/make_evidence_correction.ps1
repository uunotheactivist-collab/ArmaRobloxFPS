# MP7 model fidelity CORRECTION evidence sheet: per state, the reference frame | the Studio capture of the BEFORE model
# (model-fidelity checkpoint, captures/after) | the AFTER model (lower-body correction, captures/after_correction), each
# normalised to the reference's 1280 x 720 frame (capture scaled by 720 / viewport height, centre-cropped to 1280: both
# are FOV 70 over the picture height), then cropped to the lower-body area at full scale.
# The Studio captures are at the IN-GAME poses (the accepted reload clips): in the reload views the weapon's place is the
# clip's, so compare SHAPES (guard loop, lower front, grip, magazine); the geometry-only comparison at free poses is
# ReferenceAnalysis/Weapons/MP7/Model/Correction/final_lower/lower_<ID>.png.
# Usage: powershell -File make_evidence_correction.ps1 -Out <png>
param([string]$Out, [int]$X = 480, [int]$Y = 240, [int]$W = 560, [int]$H = 480)
Add-Type -AssemblyName System.Drawing
$root = "C:\Users\cat\Documents\RobloxMilitaryFPS"
$cap = Join-Path $root "Roblox\Tests\Weapons\MP7\MP7ModelFidelity\captures"
$ref = Join-Path $root "ReferenceAnalysis\Weapons\MP7\Model\reference"
$order = Get-Content (Join-Path $cap "before\poses.json") -Raw | ConvertFrom-Json | Select-Object -ExpandProperty order
$rows = @(@("REST", "MP7_IDLE_MID_f0180"), @("R1_f0114", "MP7_R1_SIDE_f0114"), @("R1_f0131", "MP7_R1_MAG_SEATED_f0131"),
          @("R2_f0340", "MP7_R2_MAG_APPROACH_f0340"), @("R2_f0360", "MP7_R2_SIDE_f0360"), @("R3_f0612", "MP7_R3_SIDE_f0612"),
          @("R3_f0621", "MP7_R3_MAG_SEATED_f0621"), @("R4_f0813", "MP7_R4_MAG_SEATED_f0813"))
$sheet = New-Object System.Drawing.Bitmap ($W * 3 + 8), ($H * $rows.Count + 4 * ($rows.Count - 1))
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font "Consolas", 11
$br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 0))
$bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(160, 0, 0, 0))
for ($i = 0; $i -lt $rows.Count; $i++) {
  $sid = $rows[$i][0]; $rid = $rows[$i][1]
  $idx = [array]::IndexOf($order, $sid) + 1
  $y0 = $i * ($H + 4)
  $im = [System.Drawing.Image]::FromFile((Join-Path $ref "$rid.png"))
  $g.DrawImage($im, (New-Object System.Drawing.Rectangle 0, $y0, $W, $H), $X, $Y, $W, $H, [System.Drawing.GraphicsUnit]::Pixel); $im.Dispose()
  $g.FillRectangle($bg, 0, $y0, 360, 22); $g.DrawString("REFERENCE $rid", $font, $br, 4, $y0 + 3)
  $col = 1
  foreach ($set in @(@("after", "BEFORE (model fidelity)"), @("after_correction", "AFTER (lower-body correction)"))) {
    $p = Join-Path $cap ("{0}\s{1:D3}_p1.png" -f $set[0], $idx)
    $im = [System.Drawing.Image]::FromFile($p)
    $s = 720.0 / $im.Height; $off = ($im.Width * $s - 1280) / 2
    $src = New-Object System.Drawing.RectangleF ([float](($off + $X) / $s)), ([float]($Y / $s)), ([float]($W / $s)), ([float]($H / $s))
    $x0 = $col * ($W + 4)
    $g.DrawImage($im, (New-Object System.Drawing.RectangleF $x0, $y0, $W, $H), $src, [System.Drawing.GraphicsUnit]::Pixel); $im.Dispose()
    $g.FillRectangle($bg, $x0, $y0, 470, 22); $g.DrawString(("{0}, Studio, state {1}" -f $set[1], $sid), $font, $br, $x0 + 4, $y0 + 3)
    $col++
  }
}
$g.Dispose()
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
"wrote $Out"
