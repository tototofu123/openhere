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
DWMWA_EXTENDED_FRAME_BOUNDS := 9
DWMWA_WINDOW_CORNER_PREFERENCE := 33
DWMWCP_DEFAULT := 0
DWMWCP_DONOTROUND := 1
GA_ROOT := 2
GW_OWNER := 4
GWL_EXSTYLE := -20
WS_CAPTION := 0x00C00000
WS_EX_TOOLWINDOW := 0x00000080
WS_EX_NOACTIVATE := 0x08000000
SWP_NOZORDER := 0x0004
SWP_NOSIZE := 0x0001
SWP_NOMOVE := 0x0002
SWP_FRAMECHANGED := 0x0020
SWP_NOACTIVATE := 0x0010
SWP_NOOWNERZORDER := 0x0200
SW_MAXIMIZE := 3

; ---- autostart lives in the per-user Run key, not a Startup .lnk:
; a .lnk pointing at a bare .ahk silently stops working if the AutoHotkey
; file association is ever changed or AHK is reinstalled somewhere else.
RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
RUN_NAME := "OpenHere"

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
gRunAtStartup := true
gDebug := false
gLogPath := ""
gHookCallback := 0      ; keep referenced or the hook dies
gPending := []          ; deferred re-checks / re-asserts (watchdog queue)

; ---- grouping (idea: like agent-bus rooms — a name, members, one speaker)
gGroups := []           ; live groups: {members, active, cell, gui, shown, offset, needRender}
gGroupMode := false     ; grouping mode on = click windows to select
gGroupSel := []         ; selection order
gGroupOverlays := Map() ; hwnd -> highlight gui
gGroupBanner := 0
gGroupHotkey := "^!g"
gEnabledHotkey := "^!o"
gActivateOnMove := true
gMediaProcs := Map()
gSnapHotkey := "^!s"
gTidyHotkey := "^!t"
gTaskbarHotkey := "^!b"
gGroupStyle := "overlap" 
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
; activate a window after moving it across monitors so its taskbar
; button follows (newly launched apps also come to the front)
activate_on_move=1
; launch automatically at Windows startup (per-user registry Run key)
run_at_startup=1

[debug]
; set to 1 to write a log of every decision next to this file
log=0

[grouping]
; hotkeys (AHK syntax): ^ = Ctrl, ! = Alt, + = Shift
; group mode: press once, click windows, press again to confirm
hotkey=^!g
; enable/disable the whole app
enabled_hotkey=^!o
; group tab bar: always = visible while the group exists (recommended)
;                foreground = only while a member is the active window
bar_visibility=always

[media]
; extra process names treated as media players (comma-separated):
; a monitor where one covers 70%+ is protected from new windows
; (fullscreen coverage protects any monitor regardless)
processes=

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
    gGroupHotkey := IniRead(path, "grouping", "hotkey", "^!g")
    gEnabledHotkey := IniRead(path, "grouping", "enabled_hotkey", "^!o")
    gMediaProcs := Map()
    for mp in StrSplit(IniRead(path, "media", "processes", ""), ",", " \t") {
        mp := StrLower(Trim(mp))
        if (mp != "")
            gMediaProcs[mp] := true
    }
    for mp in ["vlc.exe", "mpv.exe", "potplayermini64.exe", "potplayermini.exe",
               "wmplayer.exe", "mpc-hc64.exe", "mpc-hc.exe", "spotify.exe", "itunes.exe"]
        gMediaProcs[mp] := true
    gSnapHotkey := IniRead(path, "grouping", "snap_hotkey", "^!s")
    gTidyHotkey := IniRead(path, "grouping", "tidy_hotkey", "^!t")
    gTaskbarHotkey := IniRead(path, "grouping", "taskbar_hotkey", "^!b")
    gGroupStyle := IniRead(path, "grouping", "mode", "overlap")
    gBarVisibility := IniRead(path, "grouping", "bar_visibility", "always")
    gActivateOnMove := IniRead(path, "general", "activate_on_move", "1") = "1"
    gRunAtStartup := IniRead(path, "general", "run_at_startup", "1") = "1"

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
; Autostart — per-user Run key. Rewritten on every launch, so moving
; the folder or reinstalling AutoHotkey repairs the entry by itself.
; The old Startup-folder .lnk is removed once and never recreated
; (a .lnk aimed at a bare .ahk depends on a file association).
; ------------------------------------------------------------
StartupCommand() {
    if A_IsCompiled
        return '"' A_ScriptFullPath '"'
    return '"' A_AhkPath '" "' A_ScriptFullPath '"'
}

ApplyRunAtStartup() {
    global gRunAtStartup, RUN_KEY, RUN_NAME
    legacy := A_Startup "\OpenHere.lnk"
    if FileExist(legacy)
        try FileDelete(legacy)
    if gRunAtStartup
        RegWrite(StartupCommand(), "REG_SZ", RUN_KEY, RUN_NAME)
    else
        RegDelete(RUN_KEY, RUN_NAME)
}

SetRunAtStartup(enabled) {
    global gRunAtStartup
    gRunAtStartup := enabled
    IniWrite(enabled ? "1" : "0", ConfigPath(), "general", "run_at_startup")
    ApplyRunAtStartup()
    RefreshTray()
    Log("run at startup " (enabled ? "enabled" : "disabled"))
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

; The window rect includes Windows' invisible resize borders, so two
; windows placed at adjacent cell edges visibly stop short of each other.
; DWM's extended frame bounds are the rectangle you actually SEE — use
; that for all placement decisions. Fall back to WindowRect when DWM has
; no usable answer (minimized/island windows report nonsense bounds).
VisibleRect(hwnd) {
    win := WindowRect(hwnd)
    fb := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint",
               DWMWA_EXTENDED_FRAME_BOUNDS, "ptr", fb, "uint", 16, "int") != 0
        return win
    vis := {left: NumGet(fb, 0, "Int"), top: NumGet(fb, 4, "Int"),
            right: NumGet(fb, 8, "Int"), bottom: NumGet(fb, 12, "Int")}
    if (vis.right <= vis.left || vis.bottom <= vis.top
        || Abs(vis.left - win.left) > 100 || Abs(vis.top - win.top) > 100
        || Abs(vis.right - win.right) > 100 || Abs(vis.bottom - win.bottom) > 100)
        return win
    return vis
}

; Windows 11 rounds floating windows but keeps snapped/maximized ones
; square. A SetWindowPos-placed window is still "floating" to DWM, so
; tiled windows would show rounded inner corners (unlike native snap).
; Mirror native snap by asking DWM not to round a window we tile.
SetWindowCorners(hwnd, square) {
    pref := square ? DWMWCP_DONOTROUND : DWMWCP_DEFAULT
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", hwnd, "uint",
            DWMWA_WINDOW_CORNER_PREFERENCE, "int*", &pref, "uint", 4, "int")
}

; ------------------------------------------------------------
; Decision filter — is this hwnd a real app window we manage?
; ------------------------------------------------------------
; returns true = manageable. Rejections are STABLE (ghost/shell — safe
; to mark seen) unless the failure is a TRANSIENT birth state (cloaked
; / titleless), in which case &transientRej is set: the caller queues a
; retry and drops the seen-mark so a later state is re-processed.
IsManageableWindow(hwnd, isRetry := false, &transientRej := false, fromHook := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    ; the hook is authoritative: a SHOW event is news even for a window
    ; a previous transient state already marked seen. The sweep stays
    ; seen-gated (it is only the backstop).
    if !isRetry && !fromHook && gSeen.Has(hwnd)
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
    ; cloaked windows are mid-launch — transient, not a ghost verdict
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
            "uint*", &cloaked, "uint", 4, "int")
    if (cloaked != 0) {
        transientRej := true
        return false
    }
    exStyle := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
    if (exStyle & WS_EX_TOOLWINDOW) || (exStyle & WS_EX_NOACTIVATE)
        return false
    ; XAML apps (Win11 notepad etc.) show the window before setting
    ; their title — transient too
    if DllCall("GetWindowTextLengthW", "ptr", hwnd, "int") = 0 {
        transientRej := true
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
; Ratio-based tiling across every monitor.
;
; A grid is described by column/row boundaries expressed as FRACTIONS
; of the cursor monitor's work area — nothing is hard-coded in pixels.
; Existing windows tell us the fractions (half / third / quarter);
; an empty monitor starts from a default 2x2 grid.
;
; Fill order is decided by the monitor's aspect ratio (the viewport
; under the cursor):
;   horizontal / landscape -> column-major: TL, BL, TR, BR
;   vertical / portrait    -> row-major:    TL, TR, BL, BR
; ------------------------------------------------------------
SnapFrac(v) {
    ; nearest "nice" fraction, or -1 when v isn't close to one
    static fracs := [0.0, 0.25, 1/3, 0.5, 2/3, 0.75, 1.0]
    best := -1, bestD := 0.045
    for f in fracs {
        d := Abs(v - f)
        if (d < bestD) {
            bestD := d
            best := f
        }
    }
    return best
}

AxisBoundaries(vals) {
    ; promote a detected fraction to a full, even grid on that axis
    third := false, quarter := false, half := false
    for v in vals {
        if (Abs(v - 1/3) < 0.01 || Abs(v - 2/3) < 0.01)
            third := true
        else if (Abs(v - 0.25) < 0.01 || Abs(v - 0.75) < 0.01)
            quarter := true
        else if (Abs(v - 0.5) < 0.01)
            half := true
    }
    if (third)
        return [0, 1/3, 2/3, 1]
    if (quarter)
        return [0, 0.25, 0.5, 0.75, 1]
    if (half)
        return [0, 0.5, 1]
    return [0, 1]
}

DefaultGrid() {
    return {cols: [0, 0.5, 1], rows: [0, 0.5, 1]}
}

DetectGrid(occ, wa) {
    waW := wa.right - wa.left, waH := wa.bottom - wa.top
    if (waW <= 0 || waH <= 0)
        return ""
    if (occ.Length = 0)
        return DefaultGrid()
    xs := [], ys := []
    for w in occ {
        lf := SnapFrac((w.l - wa.left) / waW), rf := SnapFrac((w.r - wa.left) / waW)
        tf := SnapFrac((w.t - wa.top) / waH),  bf := SnapFrac((w.b - wa.top) / waH)
        if (lf < 0 || rf < 0 || tf < 0 || bf < 0 || rf <= lf || bf <= tf)
            continue
        fw := rf - lf, fh := bf - tf
        if (fh >= 0.75) {                       ; full-height window -> column boundaries
            xs.Push(lf), xs.Push(rf)
        }
        if (fw >= 0.75) {                       ; full-width window -> row boundaries
            ys.Push(tf), ys.Push(bf)
        }
        if (fw < 0.75 && fh < 0.75) {           ; quarter-ish -> both boundaries
            xs.Push(lf), xs.Push(rf)
            ys.Push(tf), ys.Push(bf)
        }
    }
    cols := AxisBoundaries(xs), rows := AxisBoundaries(ys)
    if (cols.Length = 2 && rows.Length = 2)    ; nothing to divide -> default grid
        return DefaultGrid()
    return {cols: cols, rows: rows}
}

GridCells(grid, wa) {
    ; landscape fills down each column first (TL, BL, TR, BR);
    ; portrait fills across each row first (TL, TR, BL, BR).
    waW := wa.right - wa.left, waH := wa.bottom - wa.top
    landscape := (waW >= waH)
    cols := grid.cols, rows := grid.rows
    nCol := cols.Length - 1, nRow := rows.Length - 1
    cells := []
    addCell(c, r) => cells.Push({l: wa.left + Round(cols[c] * waW),
                                 t: wa.top  + Round(rows[r] * waH),
                                 r: wa.left + Round(cols[c + 1] * waW),
                                 b: wa.top  + Round(rows[r + 1] * waH)})
    if (landscape) {
        Loop nCol {
            c := A_Index
            Loop nRow
                addCell(c, A_Index)
        }
    } else {
        Loop nRow {
            r := A_Index
            Loop nCol
                addCell(A_Index, r)
        }
    }
    return cells
}

GridName(grid) {
    return IsObject(grid) ? (grid.cols.Length - 1) "x" (grid.rows.Length - 1) : "none"
}

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
        rc := VisibleRect(hwnd)
        l := Max(rc.left, wa.left), t := Max(rc.top, wa.top)
        r := Min(rc.right, wa.right), b := Min(rc.bottom, wa.bottom)
        if (r - l < 40 || b - t < 40)
            continue
        if ((r - l) * (b - t) < 0.08 * waW * waH)  ; tiny widgets don't dictate layout
            continue
        occ.Push({hwnd: hwnd, l: l, t: t, r: r, b: b})
    }
    return occ
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
; Snap-tidy: windows already living in a grid cell get flushed
; exactly to the cell edges. Apps drift after birth (session
; restore, self-centering); this is what makes it LOOK snapped.
; Only touches near-members: center inside the cell, size within
; 30% of the cell — never yoinks unrelated windows.
; ------------------------------------------------------------
TidyGrid(targetMon) {
    global
    wa := MonitorWorkArea(targetMon)
    occ := CollectOccupied(targetMon, 0, wa)
    grid := DetectGrid(occ, wa)
    if (grid = "")
        return
    for cell in GridCells(grid, wa) {
        cellW := cell.r - cell.l
        cellH := cell.b - cell.t
        for w in occ {
            cx := (w.l + w.r) / 2
            cy := (w.t + w.b) / 2
            if (cx < cell.l || cx > cell.r || cy < cell.t || cy > cell.b)
                continue
            if (Abs((w.r - w.l) - cellW) > cellW * 0.3 || Abs((w.b - w.t) - cellH) > cellH * 0.3)
                continue
            if (Abs(w.l - cell.l) <= 3 && Abs(w.t - cell.t) <= 3
                && Abs(w.r - cell.r) <= 3 && Abs(w.b - cell.b) <= 3)
                continue
            SetWindowPosRect(w.hwnd, cell.l, cell.t, cellW, cellH)
            Log("tidied " w.hwnd " flush into " GridName(grid) " cell")
        }
    }
}

; ------------------------------------------------------------
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
        DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
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
        rc := VisibleRect(hwnd)
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
; ------------------------------------------------------------
MoveToMonitor(hwnd, targetMon, isRetry := false) {
    wa := MonitorWorkArea(targetMon)
    Log("MoveToMonitor " hwnd " mon=" Hex(targetMon) " retry=" isRetry)
    waW := wa.right - wa.left
    waH := wa.bottom - wa.top

    minmax := WinGetMinMax(hwnd)
    rc := VisibleRect(hwnd)
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
        grid := DetectGrid(occ, wa)
        if (gPlacement = "snap")
            Log("maximized newborn " hwnd ": occ=" occ.Length " grid=" GridName(grid))
        if (gPlacement = "snap" && grid != "") {
            for cell in GridCells(grid, wa) {
                if !CellOccupied(cell, occ) {
                    WinRestore(hwnd)
                    SetWindowPosRect(hwnd, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
                    Log("snapped maximized " hwnd " into " GridName(grid) " free cell")
                    return {l: cell.l, t: cell.t, r: cell.r, b: cell.b}
                }
            }
        }
        if (gPlacement != "snap" || MonitorFromHwnd(hwnd) != targetMon) {
            ; keep it maximized, but on the target monitor
            WinRestore(hwnd)
            rc := VisibleRect(hwnd)
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
        grid := DetectGrid(occ, wa)
        Log("snap check " hwnd ": occ=" occ.Length " grid=" GridName(grid)
            " viewport=" (wa.right - wa.left >= wa.bottom - wa.top ? "horizontal" : "vertical"))
        if (grid != "") {
            for cell in GridCells(grid, wa) {
                if !CellOccupied(cell, occ) {
                    SetWindowPosRect(hwnd, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
                    Log("snapped " hwnd " into " GridName(grid) " free cell")
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
    SetWindowPosRect(hwnd, x, y, winW, winH, false)   ; centered, not tiled: keep native rounding
    Log("moved " hwnd " -> " x "," y " on monitor " Hex(targetMon))
    return {l: x, t: y, r: x + winW, b: y + winH}
}

SetWindowPosRect(hwnd, x, y, w, h, square := true) {
    ; (x,y,w,h) is the VISIBLE frame we want. Expand it by each app's
    ; invisible border so the visible edges land flush on the cell —
    ; otherwise adjacent tiles leave a thin gap of wallpaper between.
    win := WindowRect(hwnd)
    vis := VisibleRect(hwnd)
    winW := win.right - win.left, winH := win.bottom - win.top
    visW := vis.right - vis.left, visH := vis.bottom - vis.top
    if (winW > 0 && winH > 0 && visW > 0 && visH > 0) {
        x -= vis.left - win.left
        y -= vis.top - win.top
        w += winW - visW
        h += winH - visH
    }
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", x, "int", y,
            "int", w, "int", h, "uint", SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER, "int")
    SetWindowCorners(hwnd, square)
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
    ; de-escalating: 400ms, 600ms, 900ms, 1.4s, 2s, 2.8s — slow-restoring
    ; apps (Windows Terminal restores its own geometry late) get held too
    static delays := [400, 600, 900, 1400, 2000, 2800]
    idx := Max(1, Min(delays.Length, delays.Length - attempt + 1))
    QueueDeferred(hwnd, "reassert", targetMon, attempt, desired, delays[idx])
}

; deferred work runs from one persistent watchdog timer — one-shot
; SetTimer closures proved unreliable when created inside hook callbacks
QueueDeferred(hwnd, kind, targetMon := 0, attempt := 0, desired := "", delay := 400) {
    global gPending
    for item in gPending
        if (item.hwnd = hwnd && item.kind = kind)
            return
    gPending.Push({hwnd: hwnd, kind: kind, at: A_TickCount, delay: delay,
                   mon: targetMon, attempt: attempt, desired: desired})
}

Watchdog() {
    global gPending
    MaintainGroups()
    if (gPending.Length = 0)
        return
    now := A_TickCount
    remaining := []
    for item in gPending {
        if (now - item.at < item.delay) {
            remaining.Push(item)
            continue
        }
        if (item.kind = "retry") {
            HandleWindow(item.hwnd, true, false, item.attempt)
        } else if (item.kind = "tidy") {
            TidyGrid(item.mon)
        } else if (item.kind = "hotkeys") {
            RegisterHotkeys(item.attempt)
        } else if (item.kind = "activate") {
            ActivateForTaskbar(item.hwnd)
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
        cur := VisibleRect(hwnd)
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
        rc := VisibleRect(hwnd)
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
HandleWindow(hwnd, isRetry := false, fromHook := false, retryAttempt := 0) {
    global gSeen, gRules, gEnabled, gPlacement

    ; mark seen on FIRST encounter: every window is processed once by
    ; the hook or the sweep (rejected ghosts included). Retries re-enter
    ; with isRetry=true (no mark); hook events re-enter with
    ; fromHook=true (seen-check bypassed — SHOW is always news).
    transientRej := false
    ok := IsManageableWindow(hwnd, isRetry, &transientRej, fromHook)
    if !isRetry
        gSeen[hwnd] := true
    if transientRej {
        ; birth state (cloaked/titleless): keep the seen-mark (the sweep
        ; must not spin on it) and run an escalating retry chain — the
        ; hook's SHOW event usually lands first anyway
        if (retryAttempt < 4)
            QueueDeferred(hwnd, "retry", 0, retryAttempt + 1, "", 400 * 2 ** (retryAttempt + 1))
        return
    }
    if !ok
        return
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

    wasOnTarget := (MonitorFromHwnd(hwnd) = targetMon)
    if MonitorProtected(targetMon, hwnd) {
        ; A fullscreen game/video must not be covered by a snapped app — but
        ; leaving the window completely alone lets Windows open it on ANY
        ; monitor, so the user loses track of it. Land it on the cursor's
        ; monitor at its own size instead: right viewport, no tiling, no
        ; re-assert fighting the protected window.
        Log("target monitor protected — moving " hwnd " to viewport " Hex(targetMon) " without tiling")
        wa := MonitorWorkArea(targetMon)
        waW := wa.right - wa.left, waH := wa.bottom - wa.top
        wasMax := (WinGetMinMax(hwnd) = 1)
        if wasMax
            WinRestore(hwnd)
        rc := VisibleRect(hwnd)
        winW := rc.right - rc.left, winH := rc.bottom - rc.top
        x := wa.left + (waW - winW) // 2
        y := wa.top + (waH - winH) // 2
        SetWindowPosRect(hwnd, x, y, winW, winH, false)
        if wasMax
            DllCall("ShowWindow", "ptr", hwnd, "int", SW_MAXIMIZE, "int")
        ; Without foregrounding, Windows leaves the taskbar button on the
        ; monitor the window was created on — exactly the "wrong taskbar"
        ; symptom. This path used to return before reaching the normal
        ; activation below.
        if gActivateOnMove && !wasOnTarget
            QueueDeferred(hwnd, "activate",,,, 350)
        return
    }
    Log("new window " hwnd " (" proc " / " WinGetClass(hwnd) ") rule=" rule)
    desired := MoveToMonitor(hwnd, targetMon, isRetry)
    if (desired != "none") {
        ScheduleReassert(hwnd, targetMon, 6, desired)
        if (desired != "") {
            QueueDeferred(hwnd, "tidy", targetMon,,, 1400)
            ; a window moved across monitors without activation keeps its
            ; taskbar button on the old taskbar — gentle activation fixes it
            if (gActivateOnMove && !wasOnTarget)
                QueueDeferred(hwnd, "activate",,,, 350)
        }
    }
}

PruneSeen() {
    global gSeen
    for hwnd in gSeen.Clone()
        if !DllCall("IsWindow", "ptr", hwnd)
            gSeen.Delete(hwnd)
}

; A cold start has an empty gSeen. The WinEvent hook only reports windows
; that show AFTER it is installed, but the sweep sees the whole existing
; desktop — without priming it would treat every already-open window as
; "new" and yank them all to the cursor (then snap them into cells).
WarmupSeen() {
    global gSeen
    for hwnd in WinGetList()
        gSeen[hwnd] := true
    Log("warmup: marked " gSeen.Count " pre-existing windows as seen")
}

; safety net: the WinEvent hook occasionally misses a window show on
; this machine — sweep every 700ms and handle anything unseen. gSeen
; makes both paths idempotent.
SweepNewWindows() {
    global gSeen, gEnabled
    for hwnd in WinGetList() {
        if gSeen.Has(hwnd)
            continue
        
        if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
            continue
        try HandleWindow(hwnd)
        catch Error {
            gSeen[hwnd] := true
        }
    }
}

OnWinShow(hHook, event, hwnd, idObject, idChild, eventThread, eventTime) {
    ; OBJID_WINDOW (0) with index 0 marks the window object itself
    if (idObject != 0 || idChild != 0)
        return
    try HandleWindow(hwnd, false, true)
    catch Error as err {
        ; any throw here silently drops the window — always log it
        try Log("HOOK ERROR hwnd=" hwnd ": " err.Message " in " err.What)
        gSeen[hwnd] := true
    }
}

; ------------------------------------------------------------
; Tray
; ------------------------------------------------------------
BuildTray() {
    global
    A_IconTip := "OpenHere — apps open where you are"

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Enabled`t(what makes windows follow you)", MenuToggleEnabled)
    A_TrayMenu.Add("Snap into empty space", MenuToggleSnap)
    A_TrayMenu.Add("Run at startup", MenuToggleStartup)
    A_TrayMenu.Add()  ; separator
    A_TrayMenu.Add()
    A_TrayMenu.Add("Group windows`t" gGroupHotkey, (*) => GroupHotkey())
    A_TrayMenu.Add("Snap active window`t" gSnapHotkey, (*) => SnapActiveWindow())
    A_TrayMenu.Add("Tidy this monitor`t" gTidyHotkey, (*) => TidyNow())
    A_TrayMenu.Add("Fix active taskbar button`t" gTaskbarHotkey, (*) => RefreshActiveTaskbar())
    A_TrayMenu.Add("Edit rules...", MenuEditRules)
    A_TrayMenu.Add("Reload rules", MenuReloadRules)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Quit", MenuQuit)
    A_TrayMenu.Click := 1
    A_TrayMenu.Default := "Enabled`t(what makes windows follow you)"
    RefreshTray()
}

RefreshTray() {
    global gEnabled, gPlacement, gRunAtStartup
    if gEnabled
        A_TrayMenu.Check("Enabled`t(what makes windows follow you)")
    else
        A_TrayMenu.Uncheck("Enabled`t(what makes windows follow you)")
    if (gPlacement = "snap")
        A_TrayMenu.Check("Snap into empty space")
    else
        A_TrayMenu.Uncheck("Snap into empty space")
    if gRunAtStartup
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
    UpdateTrayIcon()
    UpdateDesktopShortcutIcon()
}

; ---- tray icon: the logo; a left-click is the enable/disable toggle
TrayIconPath(on) {
    return LatestIcon(on ? "tray-on-" : "tray-off-")
}

; icons are hash-versioned by the generator — glob for the newest so the
; shell icon cache can never serve a stale render
LatestIcon(prefix) {
    best := ""
    bestTime := 0
    for dir in [A_ScriptDir "\assets\", A_ScriptDir "\..\assets\"]
    {
        Loop Files, dir prefix "*.ico"
        {
            if (A_LoopFileTimeModified > bestTime)
            {
                bestTime := A_LoopFileTimeModified
                best := A_LoopFileFullPath
            }
        }
    }
    return best
}

UpdateTrayIcon() {
    global
    p := TrayIconPath(gEnabled)
    if (p != "")
        TraySetIcon(p)
    A_IconTip := gEnabled ? "OpenHere — ON (left-click to pause)" : "OpenHere — OFF (left-click to resume)"
}

OnTrayIconMsg(wParam, lParam, msg, hwnd) {
    global
    if (lParam = 0x202)          ; WM_LBUTTONUP on the tray icon
        MenuToggleEnabled()
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
    global gRunAtStartup
    SetRunAtStartup(!gRunAtStartup)
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
try ApplyRunAtStartup()   ; self-heal the Run key (path/AHK may have moved)
catch Error as err
    Log("autostart registration failed: " err.Message)
BuildTray()
CoordMode "Mouse", "Screen"   ; v2 defaults to Client-relative — placement needs screen coords
Persistent()   ; v2: tray-only scripts exit when startup ends unless marked persistent
SetTimer(Watchdog, 400)   ; drains the deferred re-check / re-assert queue + group upkeep
WarmupSeen()   ; never treat the windows you already had as "new" on launch
SetTimer(SweepNewWindows, 700)   ; hook fallback: catch windows the hook missed
RegisterHotkeys()
OnMessage(0x404, OnTrayIconMsg)   ; tray icon left-click = toggle
try WriteToggleHelper()
catch Error as err
    Log("toggle helper failed: " err.Message)
try EnsureDesktopShortcut()
catch Error as err
    Log("desktop shortcut failed: " err.Message)
gHookCallback := CallbackCreate(OnWinShow)
gHookHandle := DllCall("SetWinEventHook",
    "uint", EVENT_OBJECT_SHOW, "uint", EVENT_OBJECT_SHOW,
    "ptr", 0, "ptr", gHookCallback,
    "uint", 0, "uint", 0,
    "uint", WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS, "ptr")
if !gHookHandle
    Log("SetWinEventHook FAILED — falling back is required (this should not happen)")
Log("OpenHere running; hook=" Hex(gHookHandle) " ini=" ConfigPath())

; ============================================================
;  Grouping — press the group hotkey, click the windows you want
;  (translucent highlight, click again to unselect), press the
;  hotkey again to confirm. Members stack into one cell with a
;  floating tab bar: click a tab to switch, arrows when there are
;  more tabs than fit, bar visible only while a member is active.
;  Vocabulary borrowed from agent-bus: a group is a room; the
;  active member is the speaker.
; ============================================================

#HotIf gGroupMode
~LButton::GroupModeClick()
Esc::GroupEsc()
#HotIf

GroupEsc() {
    global
    if gGroupMode
        CancelGroupMode()
}

RegisterHotkeys(attempt := 5) {
    global
    ok := true
    try Hotkey(gGroupHotkey, GroupHotkey)
    catch Error as err {
        ok := false
        Log("hotkey '" gGroupHotkey "' not registered: " err.Message)
    }
    try Hotkey(gSnapHotkey, SnapActiveWindow)
    catch Error as err {
        ok := false
        Log("hotkey '" gSnapHotkey "' not registered: " err.Message)
    }
    try Hotkey(gTidyHotkey, TidyNow)
    catch Error as err {
        ok := false
        Log("hotkey '" gTidyHotkey "' not registered: " err.Message)
    }
    try Hotkey(gEnabledHotkey, MenuToggleEnabled)
    catch Error as err {
        ok := false
        Log("hotkey '" gEnabledHotkey "' not registered: " err.Message)
    }
    try Hotkey(gTaskbarHotkey, RefreshActiveTaskbar)
    catch Error as err {
        ok := false
        Log("hotkey '" gTaskbarHotkey "' not registered: " err.Message)
    }
    if (!ok && attempt > 0) {
        ; a just-killed previous instance can still hold the hotkeys
        ; for a moment — retry through the watchdog
        gPending.Push({hwnd: 0, kind: "hotkeys", at: A_TickCount, delay: 1000,
                       mon: 0, attempt: attempt - 1, desired: ""})
    }
    Log("hotkeys ready (ok=" (ok ? "1" : "0") ", attempt " (6 - attempt) "/5): group=" gGroupHotkey " snap=" gSnapHotkey " tidy=" gTidyHotkey " taskbar=" gTaskbarHotkey)
}

GroupHotkey(hkName := "") {
    global
    if gGroupMode
        ConfirmGroup()
    else
        StartGroupMode()
}

StartGroupMode() {
    global
    if gGroupMode
        return
    gGroupMode := true
    gGroupSel := []
    gGroupBanner := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000 +E0x20")
    gGroupBanner.BackColor := "0B3D91"
    gGroupBanner.MarginX := 10
    gGroupBanner.MarginY := 4
    gGroupBanner.Add("Text", "cFFFFFF", "GROUPING — click windows to add (click again removes) · " gGroupHotkey " to confirm · Esc cancels")
    gGroupBanner.Show("x" (A_ScreenWidth // 2 - 260) " y8 NA")
    Log("grouping mode ON")
}

CancelGroupMode() {
    global
    if !gGroupMode
        return
    ClearOverlays()
    try gGroupBanner.Destroy()
    gGroupBanner := 0
    gGroupMode := false
    Log("grouping mode cancelled")
}

ClearOverlays() {
    global gGroupOverlays
    for hwnd, g in gGroupOverlays
        try g.Destroy()
    gGroupOverlays := Map()
}

GroupModeClick() {
    global
        if !gGroupMode
        return
    MouseGetPos ,, &w
    Log("group-click raw w=" w)
    if !w
        return
    if (StrLower(WinGetProcessName(w)) = StrLower(WinGetProcessName(A_ScriptHwnd)))
        return                                   ; our own GUIs
    cls := WinGetClass(w)
    if (cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd")
        return                                   ; desktop / taskbar
    for i, m in gGroupSel {
        if (m = w) {
            gGroupSel.RemoveAt(i)
            if gGroupOverlays.Has(w) {
                gGroupOverlays[w].Destroy()
                gGroupOverlays.Delete(w)
            }
            Log("group-select removed " w " (" gGroupSel.Length " selected)")
            return
        }
    }
    if (gGroupSel.Length >= 12) {
        Log("group-select limit reached (12)")
        return
    }
    gGroupSel.Push(w)
    AddOverlay(w)
    Log("group-select added " w " (" gGroupSel.Length " selected)")
}

AddOverlay(hwnd) {
    global gGroupOverlays
    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x20 +E0x80000 +E0x08000000")
    g.BackColor := "00A0E9"
    rc := VisibleRect(hwnd)
    g.Show("x" (rc.left - 3) " y" (rc.top - 3) " w" (rc.right - rc.left + 6) " h" (rc.bottom - rc.top + 6) " NA")
    WinSetTransparent(110, g)
    gGroupOverlays[hwnd] := g
}

ConfirmGroup() {
    global
    sel := gGroupSel.Clone()
    ClearOverlays()
    try gGroupBanner.Destroy()
    gGroupBanner := 0
    gGroupMode := false
    if (sel.Length < 2) {
        Log("group needs 2+ windows (" sel.Length " selected) — cancelled")
        return
    }
    activeHwnd := sel[sel.Length]                ; last clicked = the speaker
    mon := MonitorFromHwnd(activeHwnd)
    wa := MonitorWorkArea(mon)

    ; home cell: the grid cell the speaker is in; if the monitor has no
    ; grid, the group stacks where the speaker is right now
    cell := ""
    occ := CollectOccupied(mon, 0, wa)
    grid := DetectGrid(occ, wa)
    if (grid != "") {
        rc := VisibleRect(activeHwnd)
        cx := (rc.left + rc.right) / 2
        cy := (rc.top + rc.bottom) / 2
        for c in GridCells(grid, wa) {
            if (cx > c.l && cx < c.r && cy > c.t && cy < c.b) {
                cell := c
                break
            }
        }
    }
    if (cell = "") {
        rc := VisibleRect(activeHwnd)
        cell := {l: rc.left, t: rc.top, r: rc.right, b: rc.bottom}
    }

    ; bring every member into the home cell — unsnapped windows
    ; get snapped by construction
    for i, h in sel {
        if (h = activeHwnd)
            continue
        if (WinGetMinMax(h) = 1)
            WinRestore(h)
        SetWindowPosRect(h, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
    }

    grp := {members: sel, active: sel.Length, cell: {l: cell.l, t: cell.t, r: cell.r, b: cell.b},
            gui: 0, shown: true, offset: 0, needRender: false}
    RenderBar(grp)
    gGroups.Push(grp)
    Log("group created: " sel.Length " members in cell " cell.l "," cell.t " (style " gGroupStyle ")")
}

RenderBar(grp) {
    try if (grp.gui) {
        grp.gui.Destroy()
        grp.gui := 0
    }
    n := grp.members.Length
    if (n = 0)
        return
    barW := grp.cell.r - grp.cell.l
    tabW := 110
    vis := Min(n, Max(1, (barW - 44) // tabW))
    if (grp.offset > n - vis)
        grp.offset := Max(0, n - vis)
    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000")
    g.BackColor := "1B1B1B"
    g.MarginX := 0
    g.MarginY := 0
    g.OnEvent("ContextMenu", (*) => Ungroup(grp))
    x := 3
    if (grp.offset > 0) {
        b1 := g.Add("Text", "x" x " y4 w18 h18 Center cE0E0E0", "<")
        b1.OnEvent("Click", (*) => (grp.offset := Max(0, grp.offset - 1), grp.needRender := true))
        x += 20
    }
    i := 0
    while (i < vis && grp.offset + i < n) {
        idx := grp.offset + i + 1
        title := WinGetTitle(grp.members[idx])
        if (StrLen(title) > 16)
            title := SubStr(title, 1, 15) "…"
        color := (idx = grp.active) ? "4FC1FF" : "B4B4B4"
        tab := g.Add("Text", "x" x " y4 w" tabW " h18 Center c" color, title)
        tab.OnEvent("Click", ActivateMember.Bind(grp, idx))
        x += tabW + 2
        i++
    }
    if (grp.offset + vis < n) {
        b2 := g.Add("Text", "x" x " y4 w18 h18 Center cE0E0E0", ">")
        b2.OnEvent("Click", (*) => (grp.offset := grp.offset + 1, grp.needRender := true))
    }
    grp.gui := g
    g.Show("x" grp.cell.l " y" grp.cell.t " w" barW " h26 NA")
    grp.shown := true
}

ActivateMember(grp, idx, *) {
    if (idx > grp.members.Length)
        return
    if GetKeyState("Ctrl", "P") {
        ; ctrl+click a tab = take that window OUT of the group
        RemoveMember(grp, idx)
        return
    }
    prev := grp.active
    grp.active := idx
    if (gGroupStyle = "minimize" && prev != idx && prev >= 1 && prev <= grp.members.Length)
        WinMinimize(grp.members[prev])
    WinActivate(grp.members[idx])
    grp.needRender := true
}

RemoveMember(grp, idx) {
    global
    h := grp.members[idx]
    grp.members.RemoveAt(idx)
    if (grp.active >= idx)
        grp.active := Max(1, grp.active - 1)
    Log("group member removed: " h " (" grp.members.Length " left)")
    if (grp.members.Length < 2) {
        Ungroup(grp)
        return
    }
    grp.needRender := true
}

Ungroup(grp) {
    global
    for i, g in gGroups
        if (g = grp) {
            gGroups.RemoveAt(i)
            break
        }
    try grp.gui.Destroy()
    grp.gui := 0
    grp.shown := false
    Log("group ungrouped — windows stay where they are")
}

MaintainGroups() {
    global gGroups
    if (gGroups.Length = 0)
        return
    fg := WinExist("A")
    alive := []
    for grp in gGroups {
        live := []
        for m in grp.members
            if DllCall("IsWindow", "ptr", m)
                live.Push(m)
        grp.members := live
        if (grp.members.Length = 0) {
            try grp.gui.Destroy()
            Log("group dissolved (no members left)")
            continue
        }
        if (grp.active > grp.members.Length)
            grp.active := grp.members.Length
        if (grp.needRender) {
            grp.needRender := false
            wasShown := grp.shown
            RenderBar(grp)
            grp.shown := wasShown
        }
        vis := true
        if (gBarVisibility = "foreground") {
            vis := false
            for m in grp.members
                if (m = fg)
                    vis := true
        }
        if (vis && !grp.shown) {
            grp.gui.Show("NA")
            grp.shown := true
        } else if (!vis && grp.shown) {
            grp.gui.Hide()
            grp.shown := false
        }
        alive.Push(grp)
    }
    gGroups := alive
}

ActivateForTaskbar(hwnd) {
    if !DllCall("IsWindow", "ptr", hwnd)
        return
    if (WinGetMinMax(hwnd) = -1)
        return
    ; Even an already-active window can keep a stale taskbar button when it was
    ; moved across monitors with SWP_NOACTIVATE — so re-foreground it anyway.
    ; Windows pins a taskbar button to the monitor where the window was last
    ; foreground. SetWindowPos + SWP_NOACTIVATE does NOT move that button, so
    ; foreground the window here. WinActivate alone is frequently refused
    ; while a fullscreen game holds foreground — attach to the foreground
    ; thread first so SetForegroundWindow is accepted, then nudge with the
    ; documented BringWindowToTop (and the classic SwitchToThisWindow when
    ; available). Do NOT restore here: that would un-maximize the window.
    fg := DllCall("GetForegroundWindow", "ptr")
    fgTid := DllCall("GetWindowThreadProcessId", "ptr", fg, "ptr", 0, "uint")
    myTid := DllCall("GetCurrentThreadId", "uint")
    attached := false
    if (fgTid && fgTid != myTid)
        attached := DllCall("AttachThreadInput", "uint", myTid, "uint", fgTid, "int", true, "int")
    try WinActivate(hwnd)
    try DllCall("BringWindowToTop", "ptr", hwnd)
    try DllCall("SwitchToThisWindow", "ptr", hwnd, "int", true)
    if attached
        DllCall("AttachThreadInput", "uint", myTid, "uint", fgTid, "int", false, "int")

    ; The taskbar pins a button to the monitor where the window was first
    ; shown. Minimizing is not enough — hide and re-add the button by briefly
    ; toggling WS_EX_TOOLWINDOW. Windows then recreates it on the monitor the
    ; window is CURRENTLY on. SWP_FRAMECHANGED applies the style change.
    ex := DllCall("GetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE, "ptr")
    if !(ex & WS_EX_TOOLWINDOW) {
        flags := SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_FRAMECHANGED
        DllCall("SetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE,
                "ptr", ex | WS_EX_TOOLWINDOW, "ptr")
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0,
                "int", 0, "int", 0, "uint", flags, "int")
        Sleep 100
        DllCall("SetWindowLongPtrW", "ptr", hwnd, "int", GWL_EXSTYLE,
                "ptr", ex & ~WS_EX_TOOLWINDOW, "ptr")
        DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0,
                "int", 0, "int", 0, "uint", flags, "int")
    }
    Log("refreshed taskbar button for " hwnd " on " Hex(MonitorFromHwnd(hwnd)))
}

; Manual fix for any window whose button is still on the wrong taskbar.
RefreshActiveTaskbar(*) {
    hwnd := WinExist("A")
    if !hwnd
        return
    ActivateForTaskbar(hwnd)
    Log("manual taskbar refresh for " hwnd)
}

SnapActiveWindow(hkName := "") {
    global
    hwnd := WinExist("A")
    if !hwnd
        return
    if (StrLower(WinGetProcessName(hwnd)) = StrLower(WinGetProcessName(A_ScriptHwnd)))
        return
    mon := MonitorFromHwnd(hwnd)
    if MonitorProtected(mon, hwnd) {
        Log("snap-active: monitor " Hex(mon) " is protected (fullscreen/media)")
        return
    }
    wa := MonitorWorkArea(mon)
    occ := CollectOccupied(mon, hwnd, wa)
    grid := DetectGrid(occ, wa)
    if (grid != "") {
        for cell in GridCells(grid, wa) {
            if !CellOccupied(cell, occ) {
                if (WinGetMinMax(hwnd) = 1)
                    WinRestore(hwnd)
                SetWindowPosRect(hwnd, cell.l, cell.t, cell.r - cell.l, cell.b - cell.t)
                ScheduleReassert(hwnd, mon, 6, {l: cell.l, t: cell.t, r: cell.r, b: cell.b})
                QueueDeferred(hwnd, "tidy", mon,,, 1400)
                Log("snap-active " hwnd " into " grid " free cell")
                return
            }
        }
    }
    Log("snap-active: no free cell for " hwnd)
}

TidyNow(hkName := "") {
    global
    pt := CursorPoint()
    mon := MonitorFromPointPacked(pt.x, pt.y)
    TidyGrid(mon)
    Log("tidy-now on monitor " Hex(mon))
}


; ---- desktop shortcut: launcher with the state-colored logo.
; The .lnk's icon file is swapped green/red whenever the state flips
; (two separate files, so the shell icon cache never goes stale).

DesktopShortcutPath() {
    return A_Desktop "\OpenHere.lnk"
}

DesktopIconPath(on) {
    return LatestIcon(on ? "desktop-on-" : "desktop-off-")
}

EnsureDesktopShortcut() {
    global
    lnk := DesktopShortcutPath()
    try {
        existed := FileExist(lnk) ? true : false
        ws := ComObject("WScript.Shell")
        sc := ws.CreateShortcut(lnk)
        changed := false
        if (sc.TargetPath != A_AhkPath) {
            sc.TargetPath := A_AhkPath
            changed := true
        }
        wantArgs := '"' A_ScriptDir "\toggle.ahk" '"'
        if (sc.Arguments != wantArgs) {
            sc.Arguments := wantArgs
            changed := true
        }
        if (sc.WorkingDirectory != A_ScriptDir) {
            sc.WorkingDirectory := A_ScriptDir
            changed := true
        }
        icon := DesktopIconPath(gEnabled)
        if (icon != "" && !InStr(sc.IconLocation, icon)) {
            sc.IconLocation := icon
            changed := true
        }
        changed := true   ; always save — triggers a shell notification so
                          ; the desktop re-renders the icon after regeneration
        sc.Save()
        Log("desktop shortcut " (existed ? "updated" : "created") " (double-click = toggle)")
    } catch Error as err
        Log("desktop shortcut failed: " err.Message)
}

; the double-click helper: toggles the running OpenHere, starts it if
; it isn't running; OpenHere (re)writes it at startup with its own path
WriteToggleHelper() {
    global
    helper := A_ScriptDir "\toggle.ahk"
    q := Chr(34)   ; the quote character — no escaped-quote spaghetti
    lines := []
    lines.Push("#Requires AutoHotkey v2.0")
    lines.Push("#SingleInstance Off")
    lines.Push("DetectHiddenWindows true")
    lines.Push("if WinExist(" q A_ScriptName " ahk_class AutoHotkey" q ")")
    lines.Push("    PostMessage 0x404, 0, 0x202")
    lines.Push("else")
    lines.Push("    Run " q A_ScriptFullPath q)
    content := ""
    for sLine in lines
        content .= sLine "`n"
    f := FileOpen(helper, "w")
    f.Write(content)
    f.Close()
    Log("toggle helper written")
}

UpdateDesktopShortcutIcon() {
    global
    lnk := DesktopShortcutPath()
    if !FileExist(lnk)
        return
    icon := DesktopIconPath(gEnabled)
    if (icon = "")
        return
    try {
        ws := ComObject("WScript.Shell")
        sc := ws.CreateShortcut(lnk)
        if !InStr(sc.IconLocation, icon) {
            sc.IconLocation := icon
            sc.Save()
            Log("desktop shortcut icon -> " (gEnabled ? "green" : "red"))
        }
    } catch Error as err
        Log("desktop icon update failed: " err.Message)
}
