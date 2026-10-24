import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

# 1. state: media processes + enabled hotkey
old = 'gGroupHotkey := "^!g"'
new = ('gGroupHotkey := "^!g"\n'
       'gEnabledHotkey := "^!o"\n'
       'gMediaProcs := Map()')
assert t.count(old) == 1, "state"
t = t.replace(old, new)

# 2. config reads
old = '    gGroupHotkey := IniRead(path, "grouping", "hotkey", "^!g")'
new = ('    gGroupHotkey := IniRead(path, "grouping", "hotkey", "^!g")\n'
       '    gEnabledHotkey := IniRead(path, "grouping", "enabled_hotkey", "^!o")\n'
       '    gMediaProcs := Map()\n'
       '    for mp in StrSplit(IniRead(path, "media", "processes", ""), ",", " \\t") {\n'
       '        mp := StrLower(Trim(mp))\n'
       '        if (mp != "")\n'
       '            gMediaProcs[mp] := true\n'
       '    }\n'
       '    for mp in ["vlc.exe", "mpv.exe", "potplayermini64.exe", "potplayermini.exe",\n'
       '               "wmplayer.exe", "mpc-hc64.exe", "mpc-hc.exe", "spotify.exe", "itunes.exe"]\n'
       '        gMediaProcs[mp] := true')
assert t.count(old) == 1, "config"
t = t.replace(old, new)

# 3. hotkey registration (retry-style RegisterHotkeys: individual try blocks)
old = '''    try Hotkey(gTidyHotkey, TidyNow)
    catch Error as err {
        ok := false
        Log("hotkey '" gTidyHotkey "' not registered: " err.Message)
    }'''
new = '''    try Hotkey(gTidyHotkey, TidyNow)
    catch Error as err {
        ok := false
        Log("hotkey '" gTidyHotkey "' not registered: " err.Message)
    }
    try Hotkey(gEnabledHotkey, MenuToggleEnabled)
    catch Error as err {
        ok := false
        Log("hotkey '" gEnabledHotkey "' not registered: " err.Message)
    }'''
assert t.count(old) == 1, "register"
t = t.replace(old, new)

# 4. MonitorProtected before the Placement section
old = """; ------------------------------------------------------------
; Placement
; ------------------------------------------------------------"""
new = """; ------------------------------------------------------------
; Protected monitors: never snap new windows onto a monitor that is
; already fully occupied — a fullscreen/maximized window (covers >=95%
; of the FULL rect, taskbar included) or a media player covering >=70%.
; If every monitor is protected, new windows are left where Windows
; puts them.
; ------------------------------------------------------------
MonitorProtected(mon, excludeHwnd) {
    global
    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi, 0)
    DllCall("GetMonitorInfoW", "ptr", mon, "ptr", mi, "ptr")
    l := NumGet(mi, 4, "Int"), t := NumGet(mi, 8, "Int")
    r := NumGet(mi, 12, "Int"), b := NumGet(mi, 16, "Int")
    fullArea := (r - l) * (b - t)

    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            continue
        if (WinGetMinMax(hwnd) = -1)
            continue
        cloaked := 0
        DllCall("dwmapi\\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
                "uint*", &cloaked, "uint", 4, "int")
        if (cloaked != 0)
            continue
        exStyle := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
        if (exStyle & WS_EX_TOOLWINDOW)
            continue
        cls := WinGetClass(hwnd)
        shellCls := false
        for ig in SHELL_CLASSES
            if (StrCompare(cls, ig, false) = 0) {
                shellCls := true
                break
            }
        if shellCls
            continue
        if (MonitorFromHwnd(hwnd) != mon)
            continue
        rc := WindowRect(hwnd)
        ol := Max(rc.left, l), ot := Max(rc.top, t)
        orr := Min(rc.right, r), ob := Min(rc.bottom, b)
        if (orr <= ol || ob <= ot)
            continue
        cover := (orr - ol) * (ob - ot) / fullArea
        if (cover >= 0.95)
            return true
        proc := StrLower(WinGetProcessName(hwnd))
        if (gMediaProcs.Has(proc) && cover >= 0.70)
            return true
    }
    return false
}

; ------------------------------------------------------------
; Placement
; ------------------------------------------------------------"""
assert t.count(old) == 1, "monitorprotected"
t = t.replace(old, new)

# 5. HandleWindow: protection check before moving
old = '''    Log("new window " hwnd " (" proc " / " WinGetClass(hwnd) ") rule=" rule)
    desired := MoveToMonitor(hwnd, targetMon, isRetry)'''
new = '''    if MonitorProtected(targetMon, hwnd) {
        Log("target monitor protected (fullscreen/media) — " hwnd " left alone")
        return
    }
    Log("new window " hwnd " (" proc " / " WinGetClass(hwnd) ") rule=" rule)
    desired := MoveToMonitor(hwnd, targetMon, isRetry)'''
assert t.count(old) == 1, "handlewindow"
t = t.replace(old, new)

# 6. SnapActiveWindow: skip protected monitors
old = '''    mon := MonitorFromHwnd(hwnd)
    wa := MonitorWorkArea(mon)
    occ := CollectOccupied(mon, hwnd, wa)'''
new = '''    mon := MonitorFromHwnd(hwnd)
    if MonitorProtected(mon, hwnd) {
        Log("snap-active: monitor " Hex(mon) " is protected (fullscreen/media)")
        return
    }
    wa := MonitorWorkArea(mon)
    occ := CollectOccupied(mon, hwnd, wa)'''
assert t.count(old) == 1, "snapactive"
t = t.replace(old, new)

# 7. config template (the template has no [grouping] section yet)
old = """[rules]
; per-app rules win over the global behavior."""
new = """[grouping]
; hotkeys (AHK syntax): ^ = Ctrl, ! = Alt, + = Shift
; group mode: press once, click windows, press again to confirm
hotkey=^!g
; enable/disable the whole app
enabled_hotkey=^!o

[media]
; extra process names treated as media players (comma-separated):
; a monitor where one covers 70%+ is protected from new windows
; (fullscreen coverage protects any monitor regardless)
processes=

[rules]
; per-app rules win over the global behavior."""
assert t.count(old) == 1, "template"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("protection + hotkey wired")
