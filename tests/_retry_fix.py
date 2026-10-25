import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
raw = io.open(p, 'rb').read().decode('utf-8').replace('\r\n', '\n')
t = raw

# 1. IsManageableWindow: skip the seen-check for retries
old = """IsManageableWindow(hwnd, isRetry := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if gSeen.Has(hwnd)
        return false"""
new = """IsManageableWindow(hwnd, isRetry := false) {
    global gSeen, SHELL_CLASSES, SHELL_PROCESSES

    if !isRetry && gSeen.Has(hwnd)
        return false"""
assert t.count(old) == 1, "filter seen-check"
t = t.replace(old, new)

# 2. HandleWindow: mark seen only on first encounter
old = """    ; mark seen at ENTRY: every window is processed exactly once by the
    ; hook or the sweep (rejected ghosts included — otherwise the sweep
    ; re-derives them every tick forever). Deferred retries call this
    ; function directly, so they are unaffected.
    gSeen[hwnd] := true
    if !IsManageableWindow(hwnd, isRetry)
        return"""
new = """    ; mark seen on FIRST encounter only: every window is processed once
    ; by the hook or the sweep (rejected ghosts included). Deferred
    ; retries re-enter with isRetry=true and bypass the mark AND the
    ; seen-check inside the filter — titleless/iconic newborns get their
    ; second chance instead of being blocked by their own seen-mark.
    if !isRetry
        gSeen[hwnd] := true
    if !IsManageableWindow(hwnd, isRetry)
        return"""
assert t.count(old) == 1, "handlewindow mark"
t = t.replace(old, new)

io.open(p, 'wb').write(t.encode('utf-8'))
print("retry bypass fixed")
