# Copies the MP7 reference-derived sounds into Roblox Studio's local content folder, where the game references them as
# rbxasset://sounds/MP7Reference/<file>. Local Studio playback only: nothing is uploaded, and the files are not part of a
# published game. Run again after every Studio update (a new version folder has an empty content\sounds\MP7Reference).
#   powershell -ExecutionPolicy Bypass -File Roblox\Assets\Audio\MP7\sync_to_studio.ps1
# Targets: the folder of every running RobloxStudioBeta.exe, else the newest Versions\version-* folder that has one.
$ErrorActionPreference = "Stop"
$src = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = Get-ChildItem -Path $src -Filter "mp7_*.wav"
if ($files.Count -eq 0) { throw "no mp7_*.wav next to this script" }
$targets = @(Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue | ForEach-Object { Split-Path -Parent $_.Path } | Select-Object -Unique)
if ($targets.Count -eq 0) {
    $targets = @(Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "RobloxStudioBeta.exe") } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.FullName })
}
if ($targets.Count -eq 0) { throw "no Roblox Studio installation found" }
foreach ($t in $targets) {
    $dst = Join-Path $t "content\sounds\MP7Reference"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    # remove files of an earlier build that are no longer in this folder
    Get-ChildItem -Path $dst -Filter "mp7_*.wav" | Where-Object { -not (Test-Path (Join-Path $src $_.Name)) } | ForEach-Object {
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
