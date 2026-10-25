import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, 'rb').read().decode('utf-8').replace('\r\n', '\n')

# 1. filter: fromHook bypasses the seen-check
old = """IsManageableWindow(hwnd, isRetry := false, &transientRej := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if !isRetry && gSeen.Has(hwnd)
        return false"""
new = """IsManageableWindow(hwnd, isRetry := false, &transientRej := false, fromHook := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    ; the hook is authoritative: a SHOW event is news even for a window
    ; a previous transient state already marked seen. The sweep stays
    ; seen-gated (it is only the backstop).
    if !isRetry && !fromHook && gSeen.Has(hwnd)
        return false"""
assert t.count(old) == 1, "filter sig"
t = t.replace(old, new)

# 2. HandleWindow entry (matches the ACTUAL current text)
sig_old = """HandleWindow(hwnd, isRetry := false) {
    global gSeen, gRules, gEnabled, gPlacement

    ; mark seen on FIRST encounter only: every window is processed once
    ; by the hook or the sweep (rejected ghosts included). Deferred
    ; retries re-enter with isRetry=true and bypass the mark AND the
    ; seen-check inside the filter \u2014 titleless/iconic newborns get their
    ; second chance instead of being blocked by their own seen-mark.
    transientRej := false
    ok := IsManageableWindow(hwnd, isRetry, &transientRej)
    if !isRetry
        gSeen[hwnd] := true
    if transientRej && !isRetry {
        gSeen.Delete(hwnd)        ; birth state \u2014 let a later state re-run
        QueueDeferred(hwnd, "retry")
        return
    }
    if !ok
        return"""
sig_new = """HandleWindow(hwnd, isRetry := false, fromHook := false, retryAttempt := 0) {
    global gSeen, gRules, gEnabled, gPlacement

    ; mark seen on FIRST encounter: every window is processed once by
    ; the hook or the sweep (rejected ghosts included). Retries re-enter
    ; with isRetry=true (no mark); hook events re-enter with
    ; fromHook=true (seen-check bypassed \u2014 SHOW is always news).
    transientRej := false
    ok := IsManageableWindow(hwnd, isRetry, &transientRej, fromHook)
    if !isRetry
        gSeen[hwnd] := true
    if transientRej {
        ; birth state (cloaked/titleless): keep the seen-mark (the sweep
        ; must not spin on it) and run an escalating retry chain \u2014 the
        ; hook's SHOW event usually lands first anyway
        if (retryAttempt < 4)
            QueueDeferred(hwnd, "retry", 0, retryAttempt + 1, "", 400 * 2 ** (retryAttempt + 1))
        return
    }
    if !ok
        return"""
assert t.count(sig_old) == 1, "handlewindow sig"
t = t.replace(sig_old, sig_new)

# 3. watchdog: retries carry the attempt
old3 = """        if (item.kind = "retry") {
            HandleWindow(item.hwnd, true)"""
new3 = """        if (item.kind = "retry") {
            HandleWindow(item.hwnd, true, false, item.attempt)"""
assert t.count(old3) == 1, "watchdog retry"
t = t.replace(old3, new3)

# 4. hook passes fromHook
old4 = """    try HandleWindow(hwnd)
    catch Error as err {"""
new4 = """    try HandleWindow(hwnd, false, true)
    catch Error as err {"""
assert t.count(old4) == 1, "hook call"
t = t.replace(old4, new4)

io.open(p, 'wb').write(t.encode('utf-8'))
print("hook-bypass + retry chain applied")
