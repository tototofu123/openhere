# Test-Placement.ps1 — one placement test
# Moves the cursor to monitor N, launches an app, and asserts the new
# window landed on the cursor's monitor (or NOT on it with -NoFollow).
#
# .\Test-Placement.ps1 -CursorMonitor 2 -LaunchExe notepad.exe -FindProcess Notepad -Expect Follow
# .\Test-Placement.ps1 -CursorMonitor 3 -LaunchExe explorer.exe -LaunchArg "C:\some\folder" -FindProcess explorer -FindClass CabinetWClass -Expect Follow

# Test-Placement.ps1 — one placement test
# Moves the cursor to a monitor chosen by GEOMETRY (EnumDisplayMonitors order
# is not stable across processes), launches an app, and asserts the new window
# landed on the cursor's monitor (or NOT on it with -Expect NoFollow).
#
# .\Test-Placement.ps1 -Target MinX -LaunchExe notepad.exe -FindProcess Notepad -Expect Follow
# .\Test-Placement.ps1 -Target MaxTop -LaunchExe explorer.exe -LaunchArg "C:\some\folder" -FindProcess explorer -FindClass CabinetWClass -Expect Follow

param(
    [Parameter(Mandatory)][ValidateSet('Primary', 'MinX', 'MaxTop')][string]$Target,
    [Parameter(Mandatory)][string]$LaunchExe,
    [string]$LaunchArg = "",
    [Parameter(Mandatory)][string]$FindProcess,
    [string]$FindClass = "",
    [Parameter(Mandatory)][ValidateSet('Follow', 'NoFollow')][string]$Expect,
    [int]$WaitMs = 2500
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")

function Select-TargetMonitor {
    $list = Get-MonitorList
    switch ($Target) {
        'Primary' { return ($list | Where-Object Primary | Select-Object -First 1) }
        'MinX'    { return ($list | Sort-Object Left | Select-Object -First 1) }
        'MaxTop'  { return ($list | Sort-Object Top -Descending | Select-Object -First 1) }
    }
}

# place the cursor and remember where it is
$m = Select-TargetMonitor
$cx = $m.Left + [int]($m.Width / 2)
$cy = $m.Top + [int]($m.Height / 2)
[OpenHereWin32]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 200
$preCursor = Get-CursorPoint
$before = Get-WindowSnapshot

# launch
if ($LaunchExe -ieq "explorer.exe") {
    Start-Process $LaunchExe -ArgumentList "`"$LaunchArg`""
} else {
    if ($LaunchArg) { Start-Process $LaunchExe -ArgumentList $LaunchArg }
    else { Start-Process $LaunchExe }
}

# wait for the window, then extra time so re-assert cycles settle
$newHwnd = Find-NewWindow -ProcessName $FindProcess -Class $FindClass -before $before
Start-Sleep -Milliseconds $WaitMs

if ($newHwnd -eq [IntPtr]::Zero) {
    "RESULT=FAIL reason=no-new-window-found target=$Target"
    exit 1
}

$winMon = Get-WindowMonitor -Hwnd $newHwnd
$curMon = Get-PointMonitor -P $preCursor
$rect = New-Object OpenHereWin32+RECT
[OpenHereWin32]::GetWindowRect($newHwnd, [ref]$rect) | Out-Null

$pass = if ($Expect -eq 'Follow') { $winMon -eq $curMon } else { $winMon -ne $curMon }
$cls = [OpenHereWin32]::ClassName($newHwnd)
"RESULT=$(if ($pass) {'PASS'} else {'FAIL'}) expect=$Expect target=$Target windowMonitor=$winMon cursorMonitor=$curMon class=$cls rect=($($rect.L),$($rect.T))-($($rect.R),$($rect.B)) hwnd=$($newHwnd.ToInt64())"
if (-not $pass) { exit 1 } else { exit 0 }
