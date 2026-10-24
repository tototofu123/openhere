import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\tools\make-icons.ps1"
t = io.open(p, encoding='utf-8').read()

old = """function New-LogoBitmap {
    param([int]$Size, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill)"""
new = """function New-LogoBitmap {
    param([int]$Size, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill,
          [string]$BgColor = "#1B1F27", [string]$MonitorColor = "#9CA3AF")"""
assert t.count(old) == 1, "sig1"
t = t.replace(old, new)

old = """    # dark rounded background
    $bg = RF (2 * $s) (2 * $s) (60 * $s) (60 * $s) (14 * $s)
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#1B1F27"))), $bg)

    # monitor outline + screen
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#9CA3AF"), (3 * $s))"""
new = """    # state-colored rounded background
    $bg = RF (2 * $s) (2 * $s) (60 * $s) (60 * $s) (14 * $s)
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($BgColor))), $bg)

    # monitor outline + screen
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($MonitorColor), (3 * $s))"""
assert t.count(old) == 1, "body"
t = t.replace(old, new)

old = """function Save-Ico {
    param([string]$Path, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill)
    $sizes = @(16, 24, 32, 48)
    $entries = New-Object System.Collections.ArrayList
    foreach ($sz in $sizes) {
        $bmp = New-LogoBitmap -Size $sz -CursorColor $CursorColor -CursorStroke $CursorStroke -ScreenFill $ScreenFill"""
new = """function Save-Ico {
    param([string]$Path, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill,
          [string]$BgColor, [string]$MonitorColor)
    $sizes = @(16, 24, 32, 48)
    $entries = New-Object System.Collections.ArrayList
    foreach ($sz in $sizes) {
        $bmp = New-LogoBitmap -Size $sz -CursorColor $CursorColor -CursorStroke $CursorStroke -ScreenFill $ScreenFill -BgColor $BgColor -MonitorColor $MonitorColor"""
assert t.count(old) == 1, "sig2"
t = t.replace(old, new)

old = '''Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-on.ico"  -CursorColor "#3FB950" -CursorStroke "#FFFFFF" -ScreenFill "#2A3140"
Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-off.ico" -CursorColor "#F85149" -CursorStroke "#FFFFFF" -ScreenFill "#232830"
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-on.ico" -CursorColor "#3FB950" -CursorStroke "#FFFFFF" -ScreenFill "#232830"
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-off.ico" -CursorColor "#F85149" -CursorStroke "#FFFFFF" -ScreenFill "#232830"'''
new = '''# ON = green background, OFF = red background; shapes in white for contrast
$on  = @{ CursorColor = "#FFFFFF"; CursorStroke = "#1B1F27"; ScreenFill = "#1F7A33"; BgColor = "#2EA043"; MonitorColor = "#FFFFFF" }
$off = @{ CursorColor = "#FFFFFF"; CursorStroke = "#1B1F27"; ScreenFill = "#8F2B2B"; BgColor = "#C93A3A"; MonitorColor = "#FFFFFF" }
Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-on.ico"      @on
Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-off.ico"     @off
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-on.ico"  @on
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-off.ico" @off'''
assert t.count(old) == 1, "calls"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("state backgrounds configured")
