#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
;  OpenHere — apps open where you are
;  A free, portable, single-exe tray utility that moves every
;  newly opened window to the monitor your mouse cursor is on.
;  Idea 032 · https://github.com/tototofu123/openhere
; ============================================================
;  How it works, in one breath:
;  Windows tells us when a new top-level window shows up.
;  We check it is a real app window (not a cloaked ghost, not
;  the shell, not an owned dialog), look where your cursor is,
;  and quietly SetWindowPos it to that monitor's work area —
;  preserving maximized state and re-asserting briefly against
;  apps that restore their own saved geometry.
; ============================================================

; ---- Per-monitor DPI awareness: without this Windows lies
; ---- about coordinates on mixed-DPI monitor setups.
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

; ---- constants
EVENT_OBJECT_SHOW   := 0x8002
WINEVENT_OUTOFCONTEXT := 0x0000
WINEVENT_SKIPOWNPROCESS := 0x0002
MONITOR_DEFAULTTONEAREST := 2
DWMWA_CLOAKED := 14
GA_ROOT := 2
GW_OWNER := 4
GWL_EXSTYLE := -20
WS_CAPTION := 0x00C00000
WS_EX_TOOLWINDOW := 0x00000080
WS_EX_NOACTIVATE := 0x08000000
SWP_NOZORDER := 0x0004
SWP_NOACTIVATE := 0x0010
SWP_NOOWNERZORDER := 0x0200
SW_MAXIMIZE := 3

; ---- windows that ARE the shell (taskbar, start, search,
; ---- action center, IME). Never managed, never moved.
SHELL_CLASSES := [
    "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW",
    "SysListView32", "TaskListThumbnailWnd", "NotifyIconOverflowWindow",
    "TopLevelWindowForOverflowXamlIsland", "XamlExplorerHostIslandWindow",
    "Windows.UI.Core.CoreWindow", "Windows.UI.Composition.DesktopWindowContentBridge"
]
SHELL_PROCESSES := [
    "searchhost.exe", "startmenuexperiencehost.exe", "shellexperiencehost.exe",
    "shellhost.exe", "applicationframehost.exe", "runtimebroker.exe",
    "textinputhost.exe", "widgets.exe", "msedgewebview2.exe"
]

; ---- state
gSeen := Map()          ; hwnd -> true (already handled)
gRules := Map()         ; "notepad.exe" -> "cursor" | "never" | "monitor:N"
gEnabled := true
gPlacement := "center"
gDebug := false
gLogPath := ""
gHookCallback := 0      ; keep referenced or the hook dies
gPending := []          ; deferred re-checks / re-asserts (watchdog queue)
gHookHandle := 0

; ------------------------------------------------------------
; Config
; ------------------------------------------------------------
ConfigPath() {
    return A_ScriptDir "\openhere.ini"
}

WriteDefaultConfig(path) {
    FileAppend(
    (
"[general]
; master switch, mirrored by the tray icon checkbox
enabled=1
; placement: snap   = fill the next free slot on the monitor
;                    (half -> other half, third -> middle third,
;                     quarter -> next quarter, half+quarter -> last quarter)
;            center = always center new windows (v0.1 behavior)
placement=snap

[debug]
; set to 1 to write a log of every decision next to this file
log=0

[rules]
; per-app rules win over the global behavior.
;   never        = this app keeps Windows' own placement memory
;   cursor       = follow the cursor (the default anyway)
;   monitor:N    = pin this app to monitor N (1-based, as in
;                  Windows display settings)
; vlc.exe=never
; obs64.exe=monitor:2
"
    ), path)
}

LoadConfig() {
    global
    path := ConfigPath()
    if !FileExist(path)
        WriteDefaultConfig(path)

    gEnabled := IniRead(path, "general", "enabled", "1") = "1"
    gPlacement := IniRead(path, "general", "placement", "snap")
    gDebug := IniRead(path, "debug", "log", "0") = "1"
    gLogPath := A_ScriptDir "\openhere.log"

    gRules := Map()
    ; parse [rules] from the file directly: IniRead cannot return a
    ; whole section in v2, and per-app rules are the escape hatch
    inRules := false
    Loop Read, path {
        line := Trim(A_LoopReadLine)
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "[") {
            inRules := (StrLower(line) = "[rules]")
            continue
        }
        if !inRules || SubStr(line, 1, 1) = ";"
            continue
        eq := InStr(line, "=")
        if !eq
            continue
        name := StrLower(RTrim(SubStr(line, 1, eq - 1)))
        rule := LTrim(SubStr(line, eq + 1))
        if (name != "")
            gRules[name] := rule
    }
    if gDebug
        Log("config loaded: enabled=" gEnabled " rules=" gRules.Count)
}

Log(text) {
    global gDebug, gLogPath
    if !gDebug
        return
    try FileAppend(A_Now "  " text "`n", gLogPath)
}

; ------------------------------------------------------------
; Win32 helpers (physical pixels, thanks to PMv2 context)
; ------------------------------------------------------------
MonitorWorkArea(hMon) {
    buf := Buffer(40, 0)
    NumPut("UInt", 40, buf, 0)
    if !DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", buf, "ptr")
        return {left: 0, top: 0, right: 0, bottom: 0}
    return {
        left:   NumGet(buf, 20, "Int"),
        top:    NumGet(buf, 24, "Int"),
        right:  NumGet(buf, 28, "Int"),
        bottom: NumGet(buf, 32, "Int")
    }
}

CursorPoint() {
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt, "int")
    return {x: NumGet(pt, 0, "Int"), y: NumGet(pt, 4, "Int")}
}

MonitorFromPointPacked(x, y) {
    packed := (y << 32) | (x & 0xFFFFFFFF)
    return DllCall("MonitorFromPoint", "int64", packed, "uint", MONITOR_DEFAULTTONEAREST, "ptr")
}

MonitorFromHwnd(hwnd) {
    return DllCall("MonitorFromWindow", "ptr", hwnd, "uint", MONITOR_DEFAULTTONEAREST, "ptr")
}

; enumerate monitors (1-based, in Windows display-settings order)
MonitorList() {
    mons := []
    cb := CallbackCreate((hMon, hdc, pRect, data) => (mons.Push(hMon), true))
    DllCall("EnumDisplayMonitors", "ptr", 0, "ptr", 0, "ptr", cb, "ptr", 0)
    CallbackFree(cb)
    return mons
}

WindowRect(hwnd) {
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", hwnd, "ptr", rc, "int")
    return {
        left:   NumGet(rc, 0, "Int"),
        top:    NumGet(rc, 4, "Int"),
        right:  NumGet(rc, 8, "Int"),
        bottom: NumGet(rc, 12, "Int")
    }
}

; ------------------------------------------------------------
; Decision filter — is this hwnd a real app window we manage?
; ------------------------------------------------------------
IsManageableWindow(hwnd, isRetry := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if gSeen.Has(hwnd)
        return false
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return false
    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        return false
    ; top-level only
    if DllCall("GetAncestor", "ptr", hwnd, "uint", GA_ROOT, "ptr") != hwnd
        return false
    ; unowned — owned dialogs follow their parent app
    if DllCall("GetWindow", "ptr", hwnd, "uint", GW_OWNER, "ptr")
        return false
    ; not a cloaked UWP/ghost window
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
            "uint*", &cloaked, "uint", 4, "int")
    if (cloaked != 0)
        return false
    exStyle := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
    if (exStyle & WS_EX_TOOLWINDOW) || (exStyle & WS_EX_NOACTIVATE)
        return false
    ; XAML apps (Win11 notepad etc.) show the window before setting
    ; its title — give it one deferred chance instead of rejecting
    if DllCall("GetWindowTextLengthW", "ptr", hwnd, "int") = 0 {
        if (isRetry)
            return false
        QueueDeferred(hwnd, "retry")
        return false
    }

    cls := WinGetClass(hwnd)
    for ignore in SHELL_CLASSES
        if (StrCompare(cls, ignore, false) = 0)
            return false
    ; content-island bridge/ghost windows (XAML/WinUI plumbing that
    ; surfaces as top-level windows) — prefix match, future-proof
    if (SubStr(cls, 1, 13) = "Microsoft.UI." || SubStr(cls, 1, 11) = "Windows.UI.")
        return false
    if (cls = "InputNonClientPointerSource" || cls = "NotepadTextBox")
        return false

    proc := StrLower(WinGetProcessName(hwnd))
    for ignore in SHELL_PROCESSES
        if (proc = ignore)
            return false
    if (proc = StrLower(A_ScriptName))       ; never manage ourselves
        return false
    return true
}

; ------------------------------------------------------------
; Snap into empty space — know what's already on the monitor and
; fill the next free slot instead of stacking on top of it.
;
;   one window on the left half  -> next fills the right half
;   one window on the left third -> next fills the middle third
;   window in the top-left 1/4   -> next top-right, then bottom-left
;   half + quarter occupied      -> next fills the remaining quarter
;   anything else                -> center, like before
; ------------------------------------------------------------
CollectOccupied(targetMon, excludeHwnd, wa) {
    occ := []
    waW := wa.right - wa.left
    waH := wa.bottom - wa.top
    for hwnd in WinGetList() {
        if (hwnd = excludeHwnd)
            continue
        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            continue
        if (WinGetMinMax(hwnd) = -1)               ; minimized
            continue
        exStyle := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
        if (exStyle & WS_EX_TOOLWINDOW)
            continue
        cloaked := 0
        DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
                "uint*", &cloaked, "uint", 4, "int")
        if (cloaked != 0)
            continue
        cls := WinGetClass(hwnd)
        if (SubStr(cls, 1, 13) = "Microsoft.UI." || SubStr(cls, 1, 11) = "Windows.UI.")
            continue
        shell := false
        for ignore in SHELL_CLASSES
            if (StrCompare(cls, ignore, false) = 0) {
                shell := true
                break
            }
        if shell
            continue
        if (MonitorFromHwnd(hwnd) != targetMon)
            continue
        rc := WindowRect(hwnd)
        l := Max(rc.left, wa.left), t := Max(rc.top, wa.top)
        r := Min(rc.right, wa.right), b := Min(rc.bottom, wa.bottom)
        if (r - l < 40 || b - t < 40)
            continue
        if ((r - l) * (b - t) < 0.08 * waW * waH)  ; tiny widgets don't dictate layout
            continue
        occ.Push({l: l, t: t, r: r, b: b})
    }
    return occ
}

DetectGrid(occ, wa) {
    waW := wa.right - wa.left
    waH := wa.bottom - wa.top
    anyShort := false
    widest := 0
    for w in occ {
        fw := (w.r - w.l) / waW
        fh := (w.b - w.t) / waH
        if (fw < 0.26 || fw > 0.74)                ; not a column-shaped window
            return ""
        if (fh < 0.8)
            anyShort := true
        if (fw > widest)
            widest := fw
    }
    if (anyShort)
        return "2x2"                               ; quarter-shaped window present
    if (widest <= 0.45)
        return "cols3"                             ; third-shaped windows
    return "cols2"                                 ; half-shaped windows
}

GridCells(grid, wa) {
    l := wa.left, t := wa.top, r := wa.right, b := wa.bottom
    midX := l + (r - l) // 2, midY := t + (b - t) // 2
    x1 := l + (r - l) // 3, x2 := l + 2 * (r - l) // 3
    if (grid = "cols2")
        return [{l: l, t: t, r: midX, b: b}, {l: midX, t: t, r: r, b: b}]
    if (grid = "cols3")
        return [{l: l, t: t, r: x1, b: b}, {l: x1, t: t, r: x2, b: b}, {l: x2, t: t, r: r, b: b}]
    ; 2x2 — reading order: top-left, top-right, bottom-left, bottom-right
    return [{l: l, t: t, r: midX, b: midY}, {l: midX, t: t, r: r, b: midY},
            {l: l, t: midY, r: midX, b: b}, {l: midX, t: midY, r: r, b: b}]
}

CellOccupied(cell, occ) {
    cellArea := (cell.r - cell.l) * (cell.b - cell.t)
    for w in occ {
        ol := Max(w.l, cell.l), ot := Max(w.t, cell.t)
        orr := Min(w.r, cell.r), ob := Min(w.b, cell.b)
        if (orr > ol && ob > ot) {
            cover := (orr - ol) * (ob - ot) / cellArea
            if (cover >= 0.4)
                return true
        }
    }
    return false
}

; ------------------------------------------------------------
; Placement
; ------------------------------------------------------------
MoveToMonitor(hwnd, targetMon, isRetry := false) {
    wa := MonitorWorkArea(targetMon)
    Log("MoveToMonitor " hwnd " mon=" Hex(targetMon) " retry=" isRetry)
    waW := wa.right - wa.left
    waH := wa.bottom - wa.top

    minmax := WinGetMinMax(hwnd)
    rc := WindowRect(hwnd)
    winW := rc.right - rc.left
    winH := rc.bottom - rc.top
    hasCaption := (DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", -16, "ptr") & WS_CAPTION) != 0

    if (!hasCaption && winW >= waW && winH >= waH) {
        ; borderless fullscreen — cover the whole target monitor
        SetWindowPosRect(hwnd, wa.left, wa.top, waW, waH)
        Log("moved fullscreen " hwnd " -> monitor " Hex(targetMon))
        return "none"
    }

    if (minmax = 1) {
        ; maximized birth state
        occ := CollectOccupied(targetMon, hwnd, wa)
        grid := occ.Length > 0 ? DetectGrid(occ, wa) : ""
        if (gPlacement = "snap")
            Log("maximized newborn " hwnd ": occ=" occ.Length " grid=" (grid = "" ? "none" : grid))
        if (gPlacement = "snap" && grid != "") {
            for cell in GridCells(grid, wa) {
                if !CellOccupied(cell, occ) {
                    WinRestore(hwnd)
                    SetWindowPosRect(hwnd, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
                    Log("snapped maximized " hwnd " into " grid " free cell")
                    return {l: cell.l, t: cell.t, r: cell.r, b: cell.b}
                }
            }
        }
        if (gPlacement != "snap" || MonitorFromHwnd(hwnd) != targetMon) {
            ; keep it maximized, but on the target monitor
            WinRestore(hwnd)
            rc := WindowRect(hwnd)
            winW := rc.right - rc.left
            winH := rc.bottom - rc.top
            x := wa.left + (waW - winW) // 2
            y := wa.top + (waH - winH) // 2
            SetWindowPosRect(hwnd, x, y, winW, winH)
            DllCall("ShowWindow", "ptr", hwnd, "int", SW_MAXIMIZE, "int")
            Log("re-maximized " hwnd " on monitor " Hex(targetMon))
            return ""
        }
        Log("left maximized on target (no grid among " occ.Length " windows)")
        return ""
    }

    if (minmax = -1) {
        ; explorer/XAML newborns can still be mid-creation at show time
        ; and report iconic before settling into maximized — one deferred
        ; re-check, then leave them alone if genuinely minimized
        if !isRetry
            QueueDeferred(hwnd, "retry")
        return "none"
    }

    ; snap: fill the next free slot if the monitor knows its layout
    if (gPlacement = "snap") {
        occ := CollectOccupied(targetMon, hwnd, wa)
        grid := occ.Length > 0 ? DetectGrid(occ, wa) : ""
        if (occ.Length > 0)
            Log("snap check " hwnd ": occ=" occ.Length " grid=" (grid = "" ? "none" : grid))
        if (grid != "") {
            for cell in GridCells(grid, wa) {
                if !CellOccupied(cell, occ) {
                    SetWindowPosRect(hwnd, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
                    Log("snapped " hwnd " into " grid " free cell")
                    return {l: cell.l, t: cell.t, r: cell.r, b: cell.b}
                }
            }
        }
    }

    ; normal window: center in the target work area
    x := wa.left + (waW - winW) // 2
    y := wa.top + (waH - winH) // 2
    x := Max(x, wa.left)
    y := Max(y, wa.top)
    SetWindowPosRect(hwnd, x, y, winW, winH)
    Log("moved " hwnd " -> " x "," y " on monitor " Hex(targetMon))
    return {l: x, t: y, r: x + winW, b: y + winH}
}

SetWindowPosRect(hwnd, x, y, w, h) {
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y,
            "int", w, "int", h, "uint", SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER, "int")
}

Hex(v) => Format("0x{:X}", v)

; ------------------------------------------------------------
; Re-assert: apps undo placements — they restore their own saved
; geometry, or maximize themselves right after showing. Hold the
; slot we chose: re-apply the exact rect until it sticks.
; desired = {l,t,r,b} rect, "" = maximized on the target monitor,
; "none" = nothing to hold.
; ------------------------------------------------------------
ScheduleReassert(hwnd, targetMon, attempt, desired) {
    QueueDeferred(hwnd, "reassert", targetMon, attempt, desired)
}

; deferred work runs from one persistent watchdog timer — one-shot
; SetTimer closures proved unreliable when created inside hook callbacks
QueueDeferred(hwnd, kind, targetMon := 0, attempt := 0, desired := "") {
    global gPending
    for item in gPending
        if (item.hwnd = hwnd && item.kind = kind)
            return
    gPending.Push({hwnd: hwnd, kind: kind, at: A_TickCount,
                   mon: targetMon, attempt: attempt, desired: desired})
}

Watchdog() {
    global gPending
    if (gPending.Length = 0)
        return
    now := A_TickCount
    remaining := []
    for item in gPending {
        if (now - item.at < 400) {
            remaining.Push(item)
            continue
        }
        if (item.kind = "retry") {
            HandleWindow(item.hwnd, true)
        } else {
            Reassert(item.hwnd, item.mon, item.attempt, item.desired)
        }
    }
    gPending := remaining
}

Reassert(hwnd, targetMon, attempt, desired) {
    global
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (desired = "") {
        if (WinGetMinMax(hwnd) = 1 && MonitorFromHwnd(hwnd) = targetMon)
            return
    } else {
        cur := WindowRect(hwnd)
        if (WinGetMinMax(hwnd) != 1
            && Abs(cur.left - desired.l) <= 8 && Abs(cur.top - desired.t) <= 8
            && Abs(cur.right - desired.r) <= 8 && Abs(cur.bottom - desired.b) <= 8)
            return
    }
    if (attempt <= 0) {
        Log("gave up re-asserting " hwnd " (" WinGetProcessName(hwnd) ")")
        return
    }
    Log("app undid the placement; re-asserting " hwnd " attempt " attempt)
    if (desired != "") {
        if (WinGetMinMax(hwnd) = 1)
            WinRestore(hwnd)
        SetWindowPosRect(hwnd, desired.l, desired.t, desired.r - desired.l, desired.b - desired.t)
    } else {
        wa := MonitorWorkArea(targetMon)
        WinRestore(hwnd)
        rc := WindowRect(hwnd)
        x := wa.left + ((wa.right - wa.left) - (rc.right - rc.left)) // 2
        y := wa.top + ((wa.bottom - wa.top) - (rc.bottom - rc.top)) // 2
        SetWindowPosRect(hwnd, x, y, rc.right - rc.left, rc.bottom - rc.top)
        DllCall("ShowWindow", "ptr", hwnd, "int", SW_MAXIMIZE, "int")
    }
    ScheduleReassert(hwnd, targetMon, attempt - 1, desired)
}

; ------------------------------------------------------------
; The decision itself
; ------------------------------------------------------------
HandleWindow(hwnd, isRetry := false) {
    global gSeen, gRules, gEnabled, gPlacement
    Log("HandleWindow " hwnd " retry=" isRetry)

    if !IsManageableWindow(hwnd, isRetry) {
        Log("rejected by filter " hwnd " retry=" isRetry)
        return
    }
    gSeen[hwnd] := true
    if (gSeen.Count > 400)
        PruneSeen()
    if !gEnabled
        return

    proc := StrLower(WinGetProcessName(hwnd))
    rule := gRules.Has(proc) ? gRules[proc] : "cursor"

    targetMon := 0
    if (rule = "never")
        return
    else if (rule = "cursor") {
        pt := CursorPoint()
        targetMon := MonitorFromPointPacked(pt.x, pt.y)
    } else if (SubStr(rule, 1, 8) = "monitor:") {
        n := Integer(SubStr(rule, 9))
        mons := MonitorList()
        if (n >= 1 && n <= mons.Length)
            targetMon := mons[n]
        else
            Log("monitor:" n " does not exist (" mons.Length " monitors)")
    } else {
        Log("unknown rule '" rule "' for " proc)
    }

    if !targetMon
        return
    ; center mode skips windows already on the right monitor;
    ; snap mode still places them into a free slot
    if (MonitorFromHwnd(hwnd) = targetMon && gPlacement != "snap")
        return

    Log("new window " hwnd " (" proc " / " WinGetClass(hwnd) ") rule=" rule)
    desired := MoveToMonitor(hwnd, targetMon, isRetry)
    if (desired != "none")
        ScheduleReassert(hwnd, targetMon, 3, desired)
}

PruneSeen() {
    global gSeen
    for hwnd in gSeen.Clone()
        if !DllCall("IsWindow", "ptr", hwnd)
            gSeen.Delete(hwnd)
}

OnWinShow(hHook, event, hwnd, idObject, idChild, eventThread, eventTime) {
    ; OBJID_WINDOW (0) with index 0 marks the window object itself
    if (idObject != 0 || idChild != 0)
        return
    Log("EVENT hwnd=" hwnd " class=" (DllCall("IsWindow", "ptr", hwnd) ? WinGetClass(hwnd) : "?"))
    try HandleWindow(hwnd)
    catch Error {
        ; elevated or half-dead window — mark seen and move on,
        ; do not spam the log on every repeated show event
        gSeen[hwnd] := true
    }
}

; ------------------------------------------------------------
; Tray
; ------------------------------------------------------------
BuildTray() {
    global
    TraySetIcon("shell32.dll", 15)   ; little monitor
    A_IconTip := "OpenHere — apps open where you are"

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Enabled`t(what makes windows follow you)", MenuToggleEnabled)
    A_TrayMenu.Add("Snap into empty space", MenuToggleSnap)
    A_TrayMenu.Add("Run at startup", MenuToggleStartup)
    A_TrayMenu.Add()  ; separator
    A_TrayMenu.Add("Edit rules...", MenuEditRules)
    A_TrayMenu.Add("Reload rules", MenuReloadRules)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Quit", MenuQuit)
    A_TrayMenu.Click := 1
    A_TrayMenu.Default := "Enabled`t(what makes windows follow you)"
    RefreshTray()
}

RefreshTray() {
    global gEnabled, gPlacement
    if gEnabled
        A_TrayMenu.Check("Enabled`t(what makes windows follow you)")
    else
        A_TrayMenu.Uncheck("Enabled`t(what makes windows follow you)")
    if (gPlacement = "snap")
        A_TrayMenu.Check("Snap into empty space")
    else
        A_TrayMenu.Uncheck("Snap into empty space")
}

MenuToggleSnap(*) {
    global
    gPlacement := (gPlacement = "snap") ? "center" : "snap"
    IniWrite(gPlacement, ConfigPath(), "general", "placement")
    RefreshTray()
    Log("toggled placement=" gPlacement)
}

MenuToggleEnabled(*) {
    global
    gEnabled := !gEnabled
    IniWrite(gEnabled ? "1" : "0", ConfigPath(), "general", "enabled")
    RefreshTray()
    Log("toggled enabled=" gEnabled)
}

MenuToggleStartup(*) {
    lnk := A_Startup "\OpenHere.lnk"
    if FileExist(lnk) {
        FileDelete(lnk)
        Log("startup shortcut removed")
    } else {
        FileCreateShortcut(A_ScriptFullPath, lnk, A_ScriptDir)
        Log("startup shortcut created")
    }
}

MenuEditRules(*) {
    path := ConfigPath()
    if !FileExist(path)
        WriteDefaultConfig(path)
    Run('notepad.exe "' path '"')
}

MenuReloadRules(*) {
    LoadConfig()
    RefreshTray()
    Log("rules reloaded")
}

MenuQuit(*) {
    ExitApp
}

; ------------------------------------------------------------
; Start
; ------------------------------------------------------------
LoadConfig()
BuildTray()
Persistent()   ; v2: tray-only scripts exit when startup ends unless marked persistent
SetTimer(Watchdog, 400)   ; drains the deferred re-check / re-assert queue
gHookCallback := CallbackCreate(OnWinShow)
gHookHandle := DllCall("SetWinEventHook",
    "uint", EVENT_OBJECT_SHOW, "uint", EVENT_OBJECT_SHOW,
    "ptr", 0, "ptr", gHookCallback,
    "uint", 0, "uint", 0,
    "uint", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS, "ptr")
if !gHookHandle
    Log("SetWinEventHook FAILED — falling back is required (this should not happen)")
Log("OpenHere running; hook=" Hex(gHookHandle) " ini=" ConfigPath())
