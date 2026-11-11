# Runs capture_states.ps1 with Studio in the foreground (an occluded Studio window stops presenting new frames, so
# PrintWindow would return a stale picture), then gives the foreground back to the window that had it.
# Usage: powershell -File run_capture.ps1 -OutDir <dir> [-TimeoutS 400]
param([string]$OutDir, [int]$TimeoutS = 400)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$r = & (Join-Path $here "studio_focus.ps1")
$r
$prev = ($r -split " ")[0]
try { & (Join-Path $here "capture_states.ps1") -OutDir $OutDir -TimeoutS $TimeoutS }
finally { & (Join-Path $here "studio_focus.ps1") -Restore $prev }
