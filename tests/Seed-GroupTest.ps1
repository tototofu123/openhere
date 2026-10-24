# Seed-GroupTest.ps1 — seed two explorer windows for the grouping test,
# write hwnds + click coordinates for the AHK driver
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")

function Get-Rect2 {
    param([IntPtr]$Hwnd)
    $r = New-Object OpenHereWin32+RECT
    [OpenHereWin32]::GetWindowRect($Hwnd, [ref]$r) | Out-Null
    return $r
}

# close leftover folder windows restored-first (so Explorer forgets "maximized")
foreach ($h in [OpenHereWin32]::TopLevelWindows()) {
    if ([OpenHereWin32]::ClassName($h) -eq 'CabinetWClass') {
        [OpenHereWin32]::ShowWindow($h, 9) | Out-Null
        Start-Sleep -Milliseconds 80
        Close-Window -Hwnd $h
    }
}
Start-Sleep -Milliseconds 600

$m = Get-MonitorList | Sort-Object Top -Descending | Select-Object -First 1
$cx = $m.Left + [int]($m.Width / 2); $cy = $m.Top + [int]($m.Height / 2)
[OpenHereWin32]::SetCursorPos($cx, $cy) | Out-Null
Start-Sleep -Milliseconds 250

$f1 = "$env:TEMP\oh-grp-a"; $f2 = "$env:TEMP\oh-grp-b"
New-Item -ItemType Directory -Force -Path $f1, $f2 | Out-Null

$before = Get-WindowSnapshot
Start-Process explorer.exe -ArgumentList "`"$f1`""
$a = Find-NewWindow -ProcessName explorer -Class CabinetWClass -before $before
Start-Sleep -Milliseconds 1800
$before2 = Get-WindowSnapshot
Start-Process explorer.exe -ArgumentList "`"$f2`""
$b = Find-NewWindow -ProcessName explorer -Class CabinetWClass -before $before2
Start-Sleep -Milliseconds 1800

if ($a -eq [IntPtr]::Zero -or $b -eq [IntPtr]::Zero) { throw "seed windows missing" }

# shape A into the left half so A and B sit in different cells
$wa = Get-WorkArea -Index $m.Index
$midX = $wa.Left + [int](($wa.Right - $wa.Left) / 2)
[OpenHereWin32]::ShowWindow($a, 9) | Out-Null
Start-Sleep -Milliseconds 150
[OpenHereWin32]::SetWindowPos($a, [IntPtr]::Zero, $wa.Left, $wa.Top, $midX - $wa.Left, $wa.Bottom - $wa.Top, 0x0014) | Out-Null
Start-Sleep -Milliseconds 2600   # let B's birth snap + A's re-asserts settle

# shape B into the right half as well (its birth snap may be mid-flight)
[OpenHereWin32]::ShowWindow($b, 9) | Out-Null
Start-Sleep -Milliseconds 150
[OpenHereWin32]::SetWindowPos($b, [IntPtr]::Zero, $midX, $wa.Top, $wa.Right - $midX, $wa.Bottom - $wa.Top, 0x0014) | Out-Null
Start-Sleep -Milliseconds 600

$ra = Get-Rect2 $a
$rb = Get-Rect2 $b
"A: $($a.ToInt64()) at ($($ra.L),$($ra.T))-($($ra.R),$($ra.B))"
"B: $($b.ToInt64()) at ($($rb.L),$($rb.T))-($($rb.R),$($rb.B))"

$x1 = [int](($ra.L + $ra.R) / 2); $y1 = [int](($ra.T + $ra.B) / 2)
$x2 = [int](($rb.L + $rb.R) / 2); $y2 = [int](($rb.T + $rb.B) / 2)
$tabX = $rb.L + 60; $tabY = $rb.T + 13

Set-Content -Path "$env:TEMP\oh-grp-hwnda.txt" -Value $a.ToInt64() -Encoding ascii
Set-Content -Path "$env:TEMP\oh-grp-hwndb.txt" -Value $b.ToInt64() -Encoding ascii
Set-Content -Path "$env:TEMP\oh-grp-cell.txt" -Value "$($rb.L),$($rb.T),$($rb.R),$($rb.B)" -Encoding ascii
Set-Content -Path "$env:TEMP\oh-grp-args.txt" -Value "$x1 $y1 $x2 $y2 $tabX $tabY" -Encoding ascii
"coords written: click A=($x1,$y1) B=($x2,$y2) tab=($tabX,$tabY)"
