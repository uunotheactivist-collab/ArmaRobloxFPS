# Brings the Studio window with a .rbxl place to the foreground (so its viewport keeps presenting fresh frames to
# PrintWindow) and prints the handle of the window that was in front, or (-Restore <handle>) gives the foreground back.
# Nothing is typed or clicked.
param([string]$Restore = "")
Add-Type @"
using System; using System.Runtime.InteropServices;
public class Fg {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
}
"@
function Tap { [Fg]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [Fg]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero) }
if ($Restore) {
  Tap; [Fg]::SetForegroundWindow([IntPtr][long]$Restore) | Out-Null
  "restored $Restore"
  return
}
$proc = Get-Process | Where-Object { $_.ProcessName -match 'RobloxStudio' -and $_.MainWindowTitle -match '\.rbxl - Roblox Studio' } | Select-Object -First 1
$h = $proc.MainWindowHandle
$prev = [Fg]::GetForegroundWindow()
Tap
if ([Fg]::IsIconic($h)) { [Fg]::ShowWindow($h, 9) | Out-Null }
[Fg]::BringWindowToTop($h) | Out-Null
[Fg]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 400
"$([long]$prev) studio_front=$([Fg]::GetForegroundWindow() -eq $h)"
