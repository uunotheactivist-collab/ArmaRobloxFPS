# Edge redness of a viewport capture, the reference's metric (ReferenceAnalysis/GrenadeFidelity M12):
# mean R - (G + B) / 2 in the side bands (the outer 30 px of a 720-px-high picture, rows 120-640 of 720) and the bottom
# band (the outer 30 px, x 100-1180 of 1280), plus a centre-low box. The capture is scaled by height to 720 and the side
# bands are taken at the capture's own left / right edges (the tint sits on the real screen edges).
# Usage: powershell -File edge_redness.ps1 -Cap <capture.png>
param([string]$Cap)
Add-Type -AssemblyName System.Drawing
$b = [System.Drawing.Bitmap]::FromFile($Cap)
$k = $b.Height / 720.0
function red($c) { return $c.R - ($c.G + $c.B) / 2 }
$sL = 0; $nL = 0; $sB = 0; $nB = 0; $sC = 0; $nC = 0
for ($y = 120; $y -lt 640; $y += 8) {
  for ($x = 0; $x -lt 30; $x += 3) { $sL += red($b.GetPixel([int]($x * $k), [int]($y * $k))); $sL += red($b.GetPixel([int]($b.Width - 1 - $x * $k), [int]($y * $k))); $nL += 2 }
}
$w720 = $b.Width / $k
for ($x = 100; $x -lt ($w720 - 100); $x += 12) { for ($y = 690; $y -lt 720; $y += 3) { $sB += red($b.GetPixel([int]($x * $k), [int]([math]::Min($y * $k, $b.Height - 1)))); $nB++ } }
for ($x = $w720 / 2 - 140; $x -lt $w720 / 2 + 140; $x += 10) { for ($y = 500; $y -lt 640; $y += 10) { $sC += red($b.GetPixel([int]($x * $k), [int]($y * $k))); $nC++ } }
$b.Dispose()
"side {0:F1}  bottom {1:F1}  centre {2:F1}" -f ($sL / $nL), ($sB / $nB), ($sC / $nC)
