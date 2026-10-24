# Screenshot-Monitors.ps1 — capture each monitor to tests\shot-<n>.png
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot "win32.ps1")

$monitors = Get-MonitorList
foreach ($m in $monitors) {
    $w = $m.Width; $h = $m.Height
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($m.Left, $m.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    $out = Join-Path $PSScriptRoot "shot-$($m.Index).png"
    $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    "saved $out ($w x $h, primary=$($m.Primary))"
}
