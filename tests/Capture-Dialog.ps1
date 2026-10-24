# Capture-Dialog.ps1 — start OpenHere, find its dialog, screenshot it
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")
Add-Type -AssemblyName System.Drawing

Start-Process "C:\Users\totot\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe" -ArgumentList "C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
Start-Sleep -Milliseconds 1800

$ahk = Get-Process AutoHotkey64 -ErrorAction SilentlyContinue
"AHK: " + (($ahk | ForEach-Object Id) -join ",")
foreach ($proc in $ahk) {
    foreach ($h in [OpenHereWin32]::TopLevelWindows()) {
        $pid2 = 0
        [OpenHereWin32]::GetWindowThreadProcessId($h, [ref]$pid2) | Out-Null
        if ($pid2 -eq $proc.Id -and [OpenHereWin32]::IsWindowVisible($h)) {
            $r = New-Object OpenHereWin32+RECT
            [OpenHereWin32]::GetWindowRect($h, [ref]$r) | Out-Null
            $w = $r.R - $r.L; $hh = $r.B - $r.T
            if ($w -le 0 -or $hh -le 0) { continue }
            "DIALOG hwnd=$($h.ToInt64()) rect=($($r.L),$($r.T))-($($r.R),$($r.B))"
            $b = New-Object System.Drawing.Bitmap($w, $hh)
            $g = [System.Drawing.Graphics]::FromImage($b)
            $g.CopyFromScreen($r.L, $r.T, 0, 0, (New-Object System.Drawing.Size($w, $hh)))
            $g.Dispose()
            $out = Join-Path $PSScriptRoot "dialog-capture.png"
            $b.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $b.Dispose()
            "saved $out"
        }
    }
}
"done"
