import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, 'rb').read().decode('utf-8').replace('\r\n', '\n')

# --- IsManageableWindow: transient rejections set a flag instead of final-reject
old = """IsManageableWindow(hwnd, isRetry := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if !isRetry && gSeen.Has(hwnd)
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
    DllCall("dwmapi\\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
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
    }"""
new = """; returns true = manageable. Rejections are STABLE (ghost/shell — safe
; to mark seen) unless the failure is a TRANSIENT birth state (cloaked
; / titleless), in which case &transientRej is set: the caller queues a
; retry and drops the seen-mark so a later state is re-processed.
IsManageableWindow(hwnd, isRetry := false, &transientRej := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if !isRetry && gSeen.Has(hwnd)
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
    DllCall("dwmapi\\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED,
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
    }"""
assert t.count(old) == 1, "filter body"
t = t.replace(old, new)

# --- HandleWindow: use the flag
old = """    if !isRetry
        gSeen[hwnd] := true
    if !IsManageableWindow(hwnd, isRetry)
        return"""
new = """    transientRej := false
    ok := IsManageableWindow(hwnd, isRetry, &transientRej)
    if !isRetry
        gSeen[hwnd] := true
    if transientRej && !isRetry {
        gSeen.Delete(hwnd)        ; birth state — let a later state re-run
        QueueDeferred(hwnd, "retry")
        return
    }
    if !ok
        return"""
assert t.count(old) == 1, "handlewindow flag use"
t = t.replace(old, new)

io.open(p, 'wb').write(t.encode('utf-8'))
print("transient-rejection restructure applied")
