# Test-Snap.ps1 — snap-into-empty-space scenarios
# Seeds windows into known shapes on the bottom-left monitor, launches a new
# explorer window, and asserts it landed in the expected free cell.
#
#   .\Test-Snap.ps1              # all scenarios
#   .\Test-Snap.ps1 -Only halves # one scenario

param([string]$Only = "")

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")

$script:pass = 0
$script:fail = 0

# monitor: bottom-most (secondary). Fresh enumeration each scenario.
function Get-TargetMonitor {
    return Get-MonitorList | Sort-Object Top -Descending | Select-Object -First 1
}

function New-TestFolder {
    $d = Join-Path $env:TEMP ("oh-snap-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Path $d | Out-Null
    return $d
}

# launch an explorer window on the target monitor (cursor goes there first)
function Launch-Explorer {
    $m = Get-TargetMonitor
    [OpenHereWin32]::SetCursorPos($m.Left + [int]($m.Width / 2), $m.Top + [int]($m.Height / 2)) | Out-Null
    Start-Sleep -Milliseconds 200
    $before = Get-WindowSnapshot
    $folder = New-TestFolder
    Start-Process explorer.exe -ArgumentList "`"$folder`""
    $h = Find-NewWindow -ProcessName explorer -Class CabinetWClass -before $before
    if ($h -eq [IntPtr]::Zero) { throw "explorer window did not appear" }
    Start-Sleep -Milliseconds 800
    return $h
}

function Assert-InCell {
    param([string]$Name, [IntPtr]$Hwnd, $Cell)
    Start-Sleep -Milliseconds 2200   # let re-assert cycles settle
    $r = New-Object OpenHereWin32+RECT
    [OpenHereWin32]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    $cx = ($r.L + $r.R) / 2; $cy = ($r.T + $r.B) / 2
    $winW = $r.R - $r.L
    $cellW = $Cell.Right - $Cell.Left
    # strict: center strictly inside the cell AND sized like the cell
    # (a centered window can touch cell corners but not match cell size)
    $inCell = ($cx -gt $Cell.Left) -and ($cx -lt $Cell.Right) -and
              ($cy -gt $Cell.Top) -and ($cy -lt $Cell.Bottom) -and
              ([math]::Abs($winW - $cellW) -lt 80)
    if ($inCell) {
        $script:pass++
        "PASS  $Name  center=($([int]$cx),$([int]$cy)) w=$([int]$winW) cell=($($Cell.Left),$($Cell.Top))-($($Cell.Right),$($Cell.Bottom)) cellW=$cellW"
    } else {
        $script:fail++
        "FAIL  $Name  center=($([int]$cx),$([int]$cy)) w=$([int]$winW) expected cell=($($Cell.Left),$($Cell.Top))-($($Cell.Right),$($Cell.Bottom)) cellW=$cellW"
    }
}

function Assert-Center {
    param([string]$Name, [IntPtr]$Hwnd, $Wa)
    Start-Sleep -Milliseconds 2200
    $r = New-Object OpenHereWin32+RECT
    [OpenHereWin32]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    $cx = ($r.L + $r.R) / 2; $cy = ($r.T + $r.B) / 2
    $wx = ($Wa.Left + $Wa.Right) / 2; $wy = ($Wa.Top + $Wa.Bottom) / 2
    if (([math]::Abs($cx - $wx) -lt 200) -and ([math]::Abs($cy - $wy) -lt 200)) {
        $script:pass++
        "PASS  $Name  center=($([int]$cx),$([int]$cy)) workarea-center=($([int]$wx),$([int]$wy))"
    } else {
        $script:fail++
        "FAIL  $Name  center=($([int]$cx),$([int]$cy)) workarea-center=($([int]$wx),$([int]$wy))"
    }
}

function Run-Scenario {
    param([string]$Name, [scriptblock]$Body)
    if ($Only -and $Only -ne $Name) { return }
    & $Body
}

# ---- halves: seed left half -> expect right half
Run-Scenario 'halves' {
    $m = Get-TargetMonitor
    $wa = Get-WorkArea -Index $m.Index
    $a = Launch-Explorer
    Set-WindowRect -Hwnd $a -L $wa.Left -T $wa.Top -R ($wa.Left + [int](($wa.Right - $wa.Left) / 2)) -B $wa.Bottom
    $cell = [pscustomobject]@{ Left = $wa.Left + [int](($wa.Right - $wa.Left) / 2); Top = $wa.Top; Right = $wa.Right; Bottom = $wa.Bottom }
    $b = Launch-Explorer
    Assert-InCell -Name "halves: half occupied -> other half" -Hwnd $b -Cell $cell
    Close-WindowSafe $a; Close-WindowSafe $b
}

# ---- thirds: seed left third -> expect middle third
Run-Scenario 'thirds' {
    $m = Get-TargetMonitor
    $wa = Get-WorkArea -Index $m.Index
    $w = $wa.Right - $wa.Left
    $a = Launch-Explorer
    Set-WindowRect -Hwnd $a -L $wa.Left -T $wa.Top -R ($wa.Left + [int]($w / 3)) -B $wa.Bottom
    $cell = [pscustomobject]@{ Left = $wa.Left + [int]($w / 3); Top = $wa.Top; Right = $wa.Left + [int](2 * $w / 3); Bottom = $wa.Bottom }
    $b = Launch-Explorer
    Assert-InCell -Name "thirds: third occupied -> middle third" -Hwnd $b -Cell $cell
    Close-WindowSafe $a; Close-WindowSafe $b
}

# ---- quarters: seed top-left quadrant -> expect top-right quadrant
Run-Scenario 'quarters' {
    $m = Get-TargetMonitor
    $wa = Get-WorkArea -Index $m.Index
    $midX = $wa.Left + [int](($wa.Right - $wa.Left) / 2)
    $midY = $wa.Top + [int](($wa.Bottom - $wa.Top) / 2)
    $a = Launch-Explorer
    Set-WindowRect -Hwnd $a -L $wa.Left -T $wa.Top -R $midX -B $midY
    $cell = [pscustomobject]@{ Left = $midX; Top = $wa.Top; Right = $wa.Right; Bottom = $midY }
    $b = Launch-Explorer
    Assert-InCell -Name "quarters: top-left 1/4 -> top-right 1/4" -Hwnd $b -Cell $cell
    Close-WindowSafe $a; Close-WindowSafe $b
}

# ---- half + quarter -> remaining bottom-right quarter
Run-Scenario 'halfquarter' {
    $m = Get-TargetMonitor
    $wa = Get-WorkArea -Index $m.Index
    $midX = $wa.Left + [int](($wa.Right - $wa.Left) / 2)
    $midY = $wa.Top + [int](($wa.Bottom - $wa.Top) / 2)
    $a = Launch-Explorer
    Set-WindowRect -Hwnd $a -L $wa.Left -T $wa.Top -R $midX -B $wa.Bottom
    $b = Launch-Explorer
    Set-WindowRect -Hwnd $b -L $midX -T $wa.Top -R $wa.Right -B $midY
    $cell = [pscustomobject]@{ Left = $midX; Top = $midY; Right = $wa.Right; Bottom = $wa.Bottom }
    $c = Launch-Explorer
    Assert-InCell -Name "halfquarter: half + quarter -> last quarter" -Hwnd $c -Cell $cell
    Close-WindowSafe $a; Close-WindowSafe $b; Close-WindowSafe $c
}

# ---- empty monitor -> plain center (regression of v0.1 behavior)
Run-Scenario 'empty' {
    $m = Get-TargetMonitor
    $wa = Get-WorkArea -Index $m.Index
    $a = Launch-Explorer
    Assert-Center -Name "empty: nothing occupied -> center" -Hwnd $a -Wa $wa
    Close-WindowSafe $a
}

"RESULT pass=$($script:pass) fail=$($script:fail)"
exit $(if ($script:fail -gt 0) { 1 } else { 0 })
