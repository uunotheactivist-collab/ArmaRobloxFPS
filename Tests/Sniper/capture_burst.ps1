# Captures the Studio play viewport repeatedly (as fast as PrintWindow allows) for the Sniper visual validation and scores
# each capture: muzzle-flash pixels (bright white-yellow) and the scope ring (dark ring of the eyepiece: the lens disc's
# bright-ish bounding box inside the centre region is not robust, so only the flash and the mean luma are scored; the
# moments are picked by the flash capture and the elapsed time).
# Usage: powershell -File capture_burst.ps1 -Dir <folder> -N 60 [-X 294 -Y 215 -W 1452 -H 753]
# Writes <Dir>\b###.png and <Dir>\scores.csv (index, ms since start, flash pixel count, mean luma).
param([string]$Dir, [int]$N = 60, [int]$X = 294, [int]$Y = 215, [int]$W = 1452, [int]$H = 753)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class SBurst {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static Bitmap Grab(IntPtr hwnd, int x, int y, int w, int hh) {
    RECT r; GetWindowRect(hwnd, out r);
    var full = new Bitmap(r.R - r.L, r.B - r.T);
    using (var g = Graphics.FromImage(full)) { var hdc = g.GetHdc(); PrintWindow(hwnd, hdc, 2); g.ReleaseHdc(hdc); }
    var crop = full.Clone(new Rectangle(x, y, w, hh), PixelFormat.Format24bppRgb); full.Dispose(); return crop;
  }
  public static double[] Score(Bitmap b) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    int stride = d.Stride; byte[] px = new byte[stride * b.Height]; Marshal.Copy(d.Scan0, px, 0, px.Length); b.UnlockBits(d);
    int flash = 0; double luma = 0; long n = 0;
    for (int yy = 0; yy < b.Height; yy += 2) for (int xx = 0; xx < b.Width; xx += 2) {
      int i = yy * stride + xx * 3; int B = px[i], G = px[i + 1], R = px[i + 2];
      if (R > 235 && G > 200 && B < 190) flash++;
      luma += 0.299 * R + 0.587 * G + 0.114 * B; n++;
    }
    return new double[] { flash, luma / n };
  }
}
"@
New-Item -ItemType Directory -Force $Dir | Out-Null
$p = Get-Process | Where-Object { $_.ProcessName -match 'RobloxStudio' -and $_.MainWindowTitle -match '\.rbxl - Roblox Studio' } | Select-Object -First 1
$hwnd = $p.MainWindowHandle
$sw = [Diagnostics.Stopwatch]::StartNew()
$rows = @("i,ms,flash_px,luma")
$bmps = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
$times = New-Object System.Collections.Generic.List[long]
for ($i = 0; $i -lt $N; $i++) {
  $times.Add($sw.ElapsedMilliseconds)
  $bmps.Add([SBurst]::Grab($hwnd, $X, $Y, $W, $H))
}
$total = $sw.ElapsedMilliseconds
for ($i = 0; $i -lt $N; $i++) {
  $s = [SBurst]::Score($bmps[$i])
  $bmps[$i].Save((Join-Path $Dir ("b{0:D3}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png); $bmps[$i].Dispose()
  $rows += ("{0},{1},{2},{3:F1}" -f $i, $times[$i], $s[0], $s[1])
}
$rows | Set-Content -Encoding ascii (Join-Path $Dir "scores.csv")
"captured $N in $total ms"
