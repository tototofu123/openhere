# Test-Tidy.ps1 — validates the snap-tidy pass on the cursor's monitor
# (read-only cursor use: launches happen wherever the cursor already is)
#
# 1. launch window A, let OpenHere place it, wait out re-asserts
# 2. simulate app drift: nudge A off its cell by (40,40)
# 3. launch window B (triggers a new placement + tidy pass)
# 4. assert A was flushed back to its cell by the tidy pass
#
# .\Test-Tidy.ps1

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")

$c = Get-CursorPoint
$mon = Get-PointMonitor -P $c
"cursor on monitor index $mon (not moving it)"
$wa = Get-WorkArea -Index $mon
$midX = $wa.Left + [int](($wa.Right - $wa.Left) / 2)
$midY = $wa.Top + [int](($wa.Bottom - $wa.Top) / 2)

function New-TestFolder {
    $d = Join-Path $env:TEMP ("oh-tidy-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $d | Out-Null
    return $d
}

function Launch-ExplorerHere {
    $before = Get-WindowSnapshot
    $f = New-TestFolder
    Start-Process explorer.exe -ArgumentList "`"$f`""
    $h = Find-NewWindow -ProcessName explorer -Class CabinetWClass -before $before
    if ($h -eq [IntPtr]::Zero) { throw "explorer window did not appear" }
    Start-Sleep -Milliseconds 500
    return $h
}

function Get-Rect {
    param([IntPtr]$Hwnd)
    $r = New-Object OpenHereWin32+RECT
    [OpenHereWin32]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    return $r
}

# --- 1. seed window A
$a = Launch-ExplorerHere
$ra = Get-Rect $a
"window A placed at ($($ra.L),$($ra.T))-($($ra.R),$($ra.B))"

# A will be shaped into the LEFT half below; its cell is the left half
$cellA = @{L = $wa.Left; T = $wa.Top; R = $midX; B = $wa.Bottom}

# --- 2. shape A into the left half (a real grid member), wait out
#        re-asserts, then simulate app drift
[OpenHereWin32]::ShowWindow($a, 9) | Out-Null
Start-Sleep -Milliseconds 150
[OpenHereWin32]::SetWindowPos($a, [IntPtr]::Zero, $wa.Left, $wa.Top, $midX - $wa.Left, $wa.Bottom - $wa.Top, 0x0014) | Out-Null
Start-Sleep -Milliseconds 3200
[OpenHereWin32]::SetWindowPos($a, [IntPtr]::Zero, $wa.Left + 40, $wa.Top + 40, $midX - $wa.Left, $wa.Bottom - $wa.Top, 0x0014) | Out-Null
Start-Sleep -Milliseconds 600
$rd = Get-Rect $a
"drifted A to ($($rd.L),$($rd.T))-($($rd.R),$($rd.B))"

# --- 3. window B triggers a fresh placement + tidy pass
$b = Launch-ExplorerHere

# --- 4. did tidy flush A back?
Start-Sleep -Milliseconds 2500
$ra2 = Get-Rect $a
$flush = ([math]::Abs($ra2.L - $cellA.L) -le 8 -and [math]::Abs($ra2.T - $cellA.T) -le 8 -and
          [math]::Abs($ra2.R - $cellA.R) -le 8 -and [math]::Abs($ra2.B - $cellA.B) -le 8)
$rb = Get-Rect $b
if ($flush) {
    "PASS  tidy flushed A back to ($($cellA.L),$($cellA.T))-($($cellA.R),$($cellA.B)) — now ($($ra2.L),$($ra2.T))-($($ra2.R),$($ra2.B))"
} else {
    "FAIL  A still drifted: ($($ra2.L),$($ra2.T))-($($ra2.R),$($ra2.B)), expected cell ($($cellA.L),$($cellA.T))-($($cellA.R),$($cellA.B))"
}
"info  B at ($($rb.L),$($rb.T))-($($rb.R),$($rb.B))"

Close-WindowSafe $a
Close-WindowSafe $b
exit $(if ($flush) { 0 } else { 1 })
