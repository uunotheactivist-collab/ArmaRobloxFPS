# Captures the Studio play viewport repeatedly (as fast as PrintWindow allows) and scores each capture for the Glock
# visual validation: green night-dot centroid / spacing (the rear dots) and muzzle-flash pixels (bright yellow-white).
# Usage: powershell -File capture_burst.ps1 -Dir <folder> -N 80 [-X 294 -Y 215 -W 1452 -H 753]
# Writes <Dir>\b###.png and <Dir>\scores.csv (index, ms since start, dots x / y / spacing, flash pixel count).
param([string]$Dir, [int]$N = 80, [int]$X = 294, [int]$Y = 215, [int]$W = 1452, [int]$H = 753)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class Burst {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static Bitmap Grab(IntPtr hwnd, int x, int y, int w, int hh) {
    RECT r; GetWindowRect(hwnd, out r);
    var full = new Bitmap(r.R - r.L, r.B - r.T);
    using (var g = Graphics.FromImage(full)) { var hdc = g.GetHdc(); PrintWindow(hwnd, hdc, 2); g.ReleaseHdc(hdc); }
    var crop = full.Clone(new Rectangle(x, y, w, hh), PixelFormat.Format24bppRgb); full.Dispose(); return crop;
  }
  // returns { dotsX, dotsY, spacing, flashPx } in viewport pixels (two largest green blobs approximated by left / right halves)
  public static double[] Score(Bitmap b) {
    var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    int stride = d.Stride; byte[] px = new byte[stride * b.Height]; Marshal.Copy(d.Scan0, px, 0, px.Length); b.UnlockBits(d);
    double sx = 0, sy = 0, n = 0; int flash = 0;
    var xs = new System.Collections.Generic.List<int>(); var ys = new System.Collections.Generic.List<int>();
    for (int yy = b.Height / 4; yy < b.Height; yy++) for (int xx = b.Width / 4; xx < b.Width * 3 / 4; xx++) {
      int i = yy * stride + xx * 3; int B = px[i], G = px[i + 1], R = px[i + 2];
      if (G > 150 && G - R > 60 && G - B > 60) { xs.Add(xx); ys.Add(yy); sx += xx; sy += yy; n++; }
      if (R > 235 && G > 200 && B < 170) flash++;
    }
    if (n < 4) return new double[] { -1, -1, -1, flash };
    double cx = sx / n, cy = sy / n;
    double lx = 0, ln = 0, rx = 0, rn = 0;
    for (int k = 0; k < xs.Count; k++) { if (xs[k] < cx) { lx += xs[k]; ln++; } else { rx += xs[k]; rn++; } }
    double spacing = (ln > 0 && rn > 0) ? rx / rn - lx / ln : -1;
    return new double[] { cx, cy, spacing, flash };
  }
}
"@
New-Item -ItemType Directory -Force $Dir | Out-Null
$p = Get-Process | Where-Object { $_.ProcessName -match 'RobloxStudio' -and $_.MainWindowTitle -match '\.rbxl - Roblox Studio' } | Select-Object -First 1
$hwnd = $p.MainWindowHandle
$sw = [Diagnostics.Stopwatch]::StartNew()
$rows = @("i,ms,dots_x,dots_y,spacing,flash_px")
for ($i = 0; $i -lt $N; $i++) {
  $ms = $sw.ElapsedMilliseconds
  $bmp = [Burst]::Grab($hwnd, $X, $Y, $W, $H)
  $s = [Burst]::Score($bmp)
  $bmp.Save((Join-Path $Dir ("b{0:D3}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  $rows += ("{0},{1},{2:F1},{3:F1},{4:F2},{5}" -f $i, $ms, $s[0], $s[1], $s[2], $s[3])
}
$rows | Set-Content -Encoding ascii (Join-Path $Dir "scores.csv")
"captured $N in $($sw.ElapsedMilliseconds) ms"
