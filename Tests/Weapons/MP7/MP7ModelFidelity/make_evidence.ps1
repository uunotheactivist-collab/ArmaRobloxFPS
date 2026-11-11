# Evidence sheet: per state, the reference frame | the Studio capture of the BEFORE model | the AFTER model, each
# normalised to the reference's 1280 x 720 frame (capture scaled by 720 / viewport height, centre-cropped to 1280: both
# are FOV 70 over the picture height), shown at half size. Usage: powershell -File make_evidence.ps1 -Out <png>
param([string]$Out)
Add-Type -AssemblyName System.Drawing
$root = "C:\Users\cat\Documents\RobloxMilitaryFPS"
$cap = Join-Path $root "Roblox\Tests\Weapons\MP7\MP7ModelFidelity\captures"
$ref = Join-Path $root "ReferenceAnalysis\Weapons\MP7\Model\reference"
$order = Get-Content (Join-Path $cap "before\poses.json") -Raw | ConvertFrom-Json | Select-Object -ExpandProperty order
# state id -> manifest id / frame of the reference
$rows = @(@("REST", "MP7_IDLE_MID_f0180"), @("R1_f0075", "MP7_R1_CANTED_f0075"), @("R1_f0125", "MP7_R1_MAG_IN_f0125"),
          @("R2_f0360", "MP7_R2_SIDE_f0360"), @("R2_f0410", "MP7_R2_CHARGING_f0410"), @("R3_f0612", "MP7_R3_SIDE_f0612"),
          @("R4_f0810", "MP7_R4_SIDE_f0810"), @("R4_f0856", "MP7_R4_CHARGING_f0856"))
$pw = 640; $ph = 360
$sheet = New-Object System.Drawing.Bitmap ($pw * 3), ($ph * $rows.Count)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = New-Object System.Drawing.Font "Consolas", 11
$br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 255, 255, 0))
for ($i = 0; $i -lt $rows.Count; $i++) {
  $sid = $rows[$i][0]; $rid = $rows[$i][1]
  $idx = [array]::IndexOf($order, $sid) + 1
  $im = [System.Drawing.Image]::FromFile((Join-Path $ref "$rid.png"))
  $g.DrawImage($im, (New-Object System.Drawing.Rectangle 0, ($i * $ph), $pw, $ph)); $im.Dispose()
  $g.DrawString("REFERENCE $rid", $font, $br, 6, $i * $ph + 6)
  $col = 1
  foreach ($set in "before", "after") {
    $p = Join-Path $cap ("{0}\s{1:D3}_p1.png" -f $set, $idx)
    $im = [System.Drawing.Image]::FromFile($p)
    $s = 720.0 / $im.Height; $wv = $im.Width * $s; $off = ($wv - 1280) / 2
    # source rectangle in capture pixels that maps to the 1280 x 720 normalised frame
    $src = New-Object System.Drawing.RectangleF ([float]($off / $s)), 0, ([float](1280 / $s)), ([float]$im.Height)
    $g.DrawImage($im, (New-Object System.Drawing.RectangleF ($col * $pw), ($i * $ph), $pw, $ph), $src, [System.Drawing.GraphicsUnit]::Pixel); $im.Dispose()
    $g.DrawString(("{0} (Studio capture, state {1})" -f $set.ToUpper(), $sid), $font, $br, $col * $pw + 6, $i * $ph + 6)
    $col++
  }
}
$g.Dispose()
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
"wrote $Out"
