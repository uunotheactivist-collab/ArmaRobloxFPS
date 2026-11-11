# MP7 model fidelity: saves the Roblox Studio play viewport for every state / phase that MP7ModelFidelityTest.Run.capture
# shows (PrintWindow: the Studio window may be behind other windows; nothing is typed or clicked).
# 1. waits for the full-viewport magenta calibration frame and takes its bounding box as the viewport rectangle;
# 2. polls the marker at the viewport's top centre (R = 10 + state index, G = 60 / 120 / 180 phase, B = 200; G = 240 end)
#    and saves <OutDir>/s<index>_p<phase>.png (the viewport crop, native pixels) when a code is seen on two polls in a row.
# Pixel scans run in a small compiled helper (GetPixel from PowerShell is too slow for a whole window).
# Usage: powershell -File capture_states.ps1 -OutDir <dir> [-TimeoutS 400]
param([string]$OutDir, [int]$TimeoutS = 400)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class PW4 {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static Bitmap Grab(IntPtr hwnd) {
    RECT r; GetWindowRect(hwnd, out r);
    Bitmap bmp = new Bitmap(r.R - r.L, r.B - r.T, PixelFormat.Format32bppArgb);
    using (Graphics g = Graphics.FromImage(bmp)) { IntPtr hdc = g.GetHdc(); PrintWindow(hwnd, hdc, 2); g.ReleaseHdc(hdc); }
    return bmp;
  }
  static byte[] Bytes(Bitmap bmp, out int stride) {
    BitmapData d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    stride = d.Stride; byte[] b = new byte[stride * bmp.Height]; Marshal.Copy(d.Scan0, b, 0, b.Length); bmp.UnlockBits(d); return b;
  }
  static bool Mag(byte[] b, int i) { return b[i + 2] >= 245 && b[i + 1] <= 10 && b[i] >= 245; }
  // bounding box of the magenta pixels (x0, y0, x1, y1) or null; requires a large area
  public static int[] MagentaRect(Bitmap bmp) {
    int stride; byte[] b = Bytes(bmp, out stride);
    int x0 = int.MaxValue, y0 = int.MaxValue, x1 = -1, y1 = -1; long n = 0;
    for (int y = 0; y < bmp.Height; y++) for (int x = 0; x < bmp.Width; x++) {
      if (Mag(b, y * stride + x * 4)) { n++; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    }
    if (n < 100000) return null;
    return new int[] { x0, y0, x1, y1, (int)n };
  }
  public static int[] Pixel(Bitmap bmp, int x, int y) { Color c = bmp.GetPixel(x, y); return new int[] { c.R, c.G, c.B }; }
}
"@
New-Item -ItemType Directory -Force $OutDir | Out-Null
$proc = Get-Process | Where-Object { $_.ProcessName -match 'RobloxStudio' -and $_.MainWindowTitle -match '\.rbxl - Roblox Studio' } | Select-Object -First 1
if (-not $proc) { throw "Studio window not found" }
$hwnd = $proc.MainWindowHandle
$t0 = Get-Date
$rect = $null
while (-not $rect -and ((Get-Date) - $t0).TotalSeconds -lt 90) {
  $bmp = [PW4]::Grab($hwnd)
  $mr = [PW4]::MagentaRect($bmp)
  if ($mr) {
    # the top bar's icons can cover parts of the top row: the rectangle is the bounding box
    $rect = @{ X = $mr[0]; Y = $mr[1]; W = $mr[2] - $mr[0] + 1; H = $mr[3] - $mr[1] + 1; N = $mr[4]; WinW = $bmp.Width; WinH = $bmp.Height }
  }
  $bmp.Dispose()
  if (-not $rect) { Start-Sleep -Milliseconds 80 }
}
if (-not $rect) { throw "no calibration frame" }
"viewport rect X=$($rect.X) Y=$($rect.Y) W=$($rect.W) H=$($rect.H) (magenta px $($rect.N), window $($rect.WinW)x$($rect.WinH))"
$rect | ConvertTo-Json | Out-File -Encoding ascii (Join-Path $OutDir "viewport_rect.json")
$mx = $rect.X + [int]($rect.W / 2); $my = $rect.Y + 5
$prev = ""; $saved = @{}
while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutS) {
  $bmp = [PW4]::Grab($hwnd)
  $c = [PW4]::Pixel($bmp, $mx, $my)
  $code = ""
  if ([math]::Abs($c[2] - 200) -le 3) {
    if ([math]::Abs($c[1] - 240) -le 3) { $code = "end" }
    else { foreach ($ph in 1, 2, 3) { if ([math]::Abs($c[1] - 60 * $ph) -le 3) { $code = "s{0:D3}_p{1}" -f ($c[0] - 10), $ph } } }
  }
  if ($code -eq "end") { $bmp.Dispose(); break }
  if ($code -ne "" -and $code -eq $prev -and -not $saved.ContainsKey($code)) {
    $crop = $bmp.Clone((New-Object System.Drawing.Rectangle $rect.X, $rect.Y, $rect.W, $rect.H), $bmp.PixelFormat)
    $crop.Save((Join-Path $OutDir "$code.png"), [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose()
    $saved[$code] = (Get-Date).ToString("HH:mm:ss.fff")
  }
  $prev = $code
  $bmp.Dispose()
}
"saved $($saved.Count) captures in $([int]((Get-Date) - $t0).TotalSeconds) s"
$saved.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Value)" } | Out-File -Encoding ascii (Join-Path $OutDir "saved.txt")
