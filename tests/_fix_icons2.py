import io
import re

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\tools\make-icons.ps1"
t = io.open(p, encoding='utf-8').read()

# 1. New-LogoBitmap: drop the dark screen fill entirely (bg shows through),
#    cursor stroke = the bg color (no dark outline)
old = """    # monitor outline + screen
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($MonitorColor), (3 * $s))
    $mon = RF (10 * $s) (12 * $s) (44 * $s) (30 * $s) (4 * $s)
    $g.DrawPath($pen, $mon)
    $scr = RF (15 * $s) (17 * $s) (34 * $s) (20 * $s) (2 * $s)
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($ScreenFill))), $scr)"""
new = """    # monitor outline (screen left empty — the state color shows through)
    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($MonitorColor), (3 * $s))
    $mon = RF (10 * $s) (12 * $s) (44 * $s) (30 * $s) (4 * $s)
    $g.DrawPath($pen, $mon)"""
assert t.count(old) == 1, "monitor"
t = t.replace(old, new)

old = """    # cursor arrow
    $pts = @(
        (New-Object System.Drawing.PointF((30 * $s), (20 * $s))),
        (New-Object System.Drawing.PointF((30 * $s), (37 * $s))),
        (New-Object System.Drawing.PointF((34.4 * $s), (32.8 * $s))),
        (New-Object System.Drawing.PointF((37.6 * $s), (39.4 * $s))),
        (New-Object System.Drawing.PointF((40.8 * $s), (37.8 * $s))),
        (New-Object System.Drawing.PointF((37.6 * $s), (31.4 * $s))),
        (New-Object System.Drawing.PointF((43.6 * $s), (31.2 * $s)))
    )
    $cursorBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($CursorColor))
    $cursorPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($CursorStroke), (1.6 * $s))
    $g.FillPolygon($cursorBrush, $pts)
    $g.DrawPolygon($cursorPen, $pts)"""
new = """    # cursor arrow (no outline — nothing dark anywhere)
    $pts = @(
        (New-Object System.Drawing.PointF((30 * $s), (20 * $s))),
        (New-Object System.Drawing.PointF((30 * $s), (37 * $s))),
        (New-Object System.Drawing.PointF((34.4 * $s), (32.8 * $s))),
        (New-Object System.Drawing.PointF((37.6 * $s), (39.4 * $s))),
        (New-Object System.Drawing.PointF((40.8 * $s), (37.8 * $s))),
        (New-Object System.Drawing.PointF((37.6 * $s), (31.4 * $s))),
        (New-Object System.Drawing.PointF((43.6 * $s), (31.2 * $s)))
    )
    $cursorBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($CursorColor))
    $g.FillPolygon($cursorBrush, $pts)"""
assert t.count(old) == 1, "cursor"
t = t.replace(old, new)

# 2. New-LogoBitmap signature: BgColor + ShapeColor only
old = """function New-LogoBitmap {
    param([int]$Size, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill,
          [string]$BgColor = "#1B1F27", [string]$MonitorColor = "#9CA3AF")"""
new = """function New-LogoBitmap {
    param([int]$Size, [string]$BgColor, [string]$ShapeColor)"""
assert t.count(old) == 1, "sig1"
t = t.replace(old, new)

t = t.replace("""    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($MonitorColor), (3 * $s))""",
              """    $pen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml($ShapeColor), (3 * $s))""")
t = t.replace("""    $gray = [System.Drawing.ColorTranslator]::FromHtml("#9CA3AF")""",
              """    $gray = [System.Drawing.ColorTranslator]::FromHtml($ShapeColor)""")
t = t.replace("""    $cursorBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($CursorColor))""",
              """    $cursorBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($ShapeColor))""")

# 3. Save-Ico: bg + shape params, hash-versioned filename, cleans old versions
old = """function Save-Ico {
    param([string]$Path, [string]$CursorColor, [string]$CursorStroke, [string]$ScreenFill,
          [string]$BgColor, [string]$MonitorColor)
    $sizes = @(16, 24, 32, 48)
    $entries = New-Object System.Collections.ArrayList
    foreach ($sz in $sizes) {
        $bmp = New-LogoBitmap -Size $sz -CursorColor $CursorColor -CursorStroke $CursorStroke -ScreenFill $ScreenFill -BgColor $BgColor -MonitorColor $MonitorColor"""
new = """function Save-Ico {
    # hash-versioned filename: a regenerated icon gets a NEW path, so the
    # shell icon cache can never serve a stale render
    param([string]$Base, [string]$BgColor, [string]$ShapeColor)
    $sizes = @(16, 24, 32, 48)
    $entries = New-Object System.Collections.ArrayList
    foreach ($sz in $sizes) {
        $bmp = New-LogoBitmap -Size $sz -BgColor $BgColor -ShapeColor $ShapeColor"""
assert t.count(old) == 1, "sig2"
t = t.replace(old, new)

old = """    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)"""
new = """    $all = New-Object System.IO.MemoryStream
    foreach ($e in $entries) { $all.Write([byte[]]$e.Data, 0, $e.Data.Length) }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash($all.ToArray()))).Replace("-", "").Substring(0, 6).ToLower()
    $sha.Dispose()
    $dir = "$PSScriptRoot\\..\\assets"
    foreach ($old in (Get-ChildItem "$dir\\$Base-*.ico" -ErrorAction SilentlyContinue)) {
        Remove-Item $old.FullName -Force
    }
    $Path = "$dir\\$Base-$hash.ico"
    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)"""
assert t.count(old) == 1, "hash"
t = t.replace(old, new)

old = """    $bw.Flush(); $bw.Close()
    "wrote $Path"
}"""
new = """    $bw.Flush(); $bw.Close()
    "wrote $Path"
    return $Path
}"""
assert t.count(old) == 1; t = t.replace(old, new)

# 4. the four calls: green on / red off, white shapes
old = """# ON = green background, OFF = red background; shapes in white for contrast
$on  = @{ CursorColor = "#FFFFFF"; CursorStroke = "#1B1F27"; ScreenFill = "#1F7A33"; BgColor = "#2EA043"; MonitorColor = "#FFFFFF" }
$off = @{ CursorColor = "#FFFFFF"; CursorStroke = "#1B1F27"; ScreenFill = "#8F2B2B"; BgColor = "#C93A3A"; MonitorColor = "#FFFFFF" }
Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-on.ico"      @on
Save-Ico -Path "$PSScriptRoot\\..\\assets\\tray-off.ico"     @off
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-on.ico"  @on
Save-Ico -Path "$PSScriptRoot\\..\\assets\\desktop-off.ico" @off"""
new = """# ON = green background, OFF = red background; shapes in white
$on  = @{ BgColor = "#2EA043"; ShapeColor = "#FFFFFF" }
$off = @{ BgColor = "#C93A3A"; ShapeColor = "#FFFFFF" }
[void]Save-Ico -Base "tray-on"      -BgColor $on.BgColor  -ShapeColor $on.ShapeColor
[void]Save-Ico -Base "tray-off"     -BgColor $off.BgColor -ShapeColor $off.ShapeColor
[void]Save-Ico -Base "desktop-on"  -BgColor $on.BgColor  -ShapeColor $on.ShapeColor
[void]Save-Ico -Base "desktop-off" -BgColor $off.BgColor -ShapeColor $off.ShapeColor"""
assert t.count(old) == 1, "calls"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("make-icons reworked: no dark colors, hash-versioned filenames")
