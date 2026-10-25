import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

# 1. state var (anchor on the grouping state block's unique neighbor)
old = 'gEnabledHotkey := "^!o"'
new = 'gEnabledHotkey := "^!o"\ngActivateOnMove := true'
assert t.count(old) == 1, "state"
t = t.replace(old, new)

# 2. config read (anchor inside LoadConfig, unique by IniRead line)
old = '    gGroupStyle := IniRead(path, "grouping", "mode", "overlap")'
new = ('    gGroupStyle := IniRead(path, "grouping", "mode", "overlap")\n'
       '    gActivateOnMove := IniRead(path, "general", "activate_on_move", "1") = "1"')
assert t.count(old) == 1, "config"
t = t.replace(old, new)

# 3. HandleWindow: queue activation after cross-monitor placements
old = """    desired := MoveToMonitor(hwnd, targetMon, isRetry)
    if (desired != "none") {
        ScheduleReassert(hwnd, targetMon, 5, desired)
        if (desired != "")
            QueueDeferred(hwnd, "tidy", targetMon,,, 1400)
    }"""
new = """    wasOnTarget := (MonitorFromHwnd(hwnd) = targetMon)
    desired := MoveToMonitor(hwnd, targetMon, isRetry)
    if (desired != "none") {
        ScheduleReassert(hwnd, targetMon, 5, desired)
        if (desired != "") {
            QueueDeferred(hwnd, "tidy", targetMon,,, 1400)
            ; a window moved across monitors without activation keeps its
            ; taskbar button on the old taskbar — gentle activation fixes it
            if (gActivateOnMove && !wasOnTarget)
                QueueDeferred(hwnd, "activate",,,, 350)
        }
    }"""
assert t.count(old) == 1, "handlewindow"
t = t.replace(old, new)

# 4. watchdog dispatch
old = """        } else if (item.kind = "hotkeys") {
            RegisterHotkeys(item.attempt)
        } else {"""
new = """        } else if (item.kind = "hotkeys") {
            RegisterHotkeys(item.attempt)
        } else if (item.kind = "activate") {
            ActivateForTaskbar(item.hwnd)
        } else {"""
assert t.count(old) == 1, "dispatch"
t = t.replace(old, new)

# 5. the activator (before SnapActiveWindow)
old = """SnapActiveWindow(hkName := "") {"""
new = """ActivateForTaskbar(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (WinGetMinMax(hwnd) = -1)
        return
    if WinActive(hwnd)
        return
    try WinActivate(hwnd)
    Log("activated " hwnd " so its taskbar button follows the move")
}

SnapActiveWindow(hkName := "") {"""
assert t.count(old) == 1, "activator"
t = t.replace(old, new)

# 6. config template
old = """placement=snap

[debug]"""
new = """placement=snap
; activate a window after moving it across monitors so its taskbar
; button follows (newly launched apps also come to the front)
activate_on_move=1

[debug]"""
assert t.count(old) == 1, "template"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("taskbar fix wired")
