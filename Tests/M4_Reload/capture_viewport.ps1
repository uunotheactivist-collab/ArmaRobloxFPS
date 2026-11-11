# Saves the Roblox Studio play viewport (window may be behind others) to <out>.png via PrintWindow.
# Usage: powershell -File capture_viewport.ps1 -Out <path.png> [-X 294 -Y 215 -W 1452 -H 753]
# The viewport rectangle is inside the maximised Studio window bitmap (measured 2026-11-06 for this layout).
param([string]$Out, [int]$X = 294, [int]$Y = 215, [int]$W = 1452, [int]$H = 753)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PW2 { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); }
"@
$p = Get-Process | Where-Object { $_.ProcessName -match 'RobloxStudio' -and $_.MainWindowTitle -match '\.rbxl - Roblox Studio' } | Select-Object -First 1
$hwnd = $p.MainWindowHandle  # (PowerShell names are case-insensitive: never call this $h, it would overwrite $H)
$r = New-Object PW2+RECT; [PW2]::GetWindowRect($hwnd, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc(); [PW2]::PrintWindow($hwnd, $hdc, 2) | Out-Null; $g.ReleaseHdc($hdc); $g.Dispose()
$crop = New-Object System.Drawing.Bitmap $W, $H
$g2 = [System.Drawing.Graphics]::FromImage($crop)
$g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $W, $H), (New-Object System.Drawing.Rectangle $X, $Y, $W, $H), [System.Drawing.GraphicsUnit]::Pixel)
$g2.Dispose()
$crop.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $crop.Dispose(); $bmp.Dispose()
"saved $Out (window $($r.R - $r.L)x$($r.B - $r.T), pid $($p.Id))"
