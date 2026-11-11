# Copies the M4 reference-derived sounds into Roblox Studio's local content folder, where the game references them as
# rbxasset://sounds/M4Reference/<file>. Local Studio playback only: nothing is uploaded, and the files are not part of a
# published game. Run again after every Studio update (a new version folder has an empty content\sounds\M4Reference).
#   powershell -ExecutionPolicy Bypass -File Roblox\Assets\Audio\M4\sync_to_studio.ps1
# Targets: the folder of every running RobloxStudioBeta.exe, else the newest Versions\version-* folder that has one.
$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = Get-ChildItem -Path $src -Filter "m4_*.wav"
if ($files.Count -eq 0) { throw "no m4_*.wav next to this script" }
$targets = @(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | ForEach-Object { Split-Path -Parent $_.Path } | Select-Object -Unique)
if ($targets.Count -eq 0) {
    $targets = @(Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "RobloxStudioBeta.exe") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName })
}
if ($targets.Count -eq 0) { throw "no Roblox Studio installation found" }
foreach ($t in $targets) {
    $dst = Join-Path $t "content\sounds\M4Reference"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    # remove files of an earlier build that are no longer in this folder (correction pass: the v1 shot files)
    Get-ChildItem -Path $dst -Filter "m4_*.wav" | Where-Object { -not (Test-Path (Join-Path $src $_.Name)) } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName
        "removed stale {0}" -f $_.Name
    }
    foreach ($f in $files) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dst $f.Name) -Force
        $a = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
        $b = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dst $f.Name)).Hash
        if ($a -ne $b) { throw "copy mismatch: $($f.Name)" }
        "{0}  {1}  -> {2}" -f $a.Substring(0, 16), $f.Name, $dst
    }
}
