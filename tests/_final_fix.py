import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
raw = io.open(p, 'rb').read()
t = raw.decode('utf-8').replace('\r\n', '\n')   # normalize sed-mangled CRLF

# 1. seen-at-entry (verified against the actual source dump)
old = """HandleWindow(hwnd, isRetry := false) {
    global gSeen, gRules, gEnabled, gPlacement
    Log("HandleWindow " hwnd " retry=" isRetry)

    if !IsManageableWindow(hwnd, isRetry) {
        Log("rejected by filter " hwnd " retry=" isRetry)
        return
    }
    gSeen[hwnd] := true
    if (gSeen.Count > 400)"""
new = """HandleWindow(hwnd, isRetry := false) {
    global gSeen, gRules, gEnabled, gPlacement

    ; mark seen at ENTRY: every window is processed exactly once by the
    ; hook or the sweep (rejected ghosts included — otherwise the sweep
    ; re-derives them every tick forever). Deferred retries call this
    ; function directly, so they are unaffected.
    gSeen[hwnd] := true
    if !IsManageableWindow(hwnd, isRetry)
        return
    if (gSeen.Count > 400)"""
assert t.count(old) == 1, "handlewindow entry"
t = t.replace(old, new)

# 2. drop the per-click debug log
old = """GroupModeClick() {
    global
    if !gGroupMode
        return"""
new = """GroupModeClick() {
    global
    if !gGroupMode
        return"""
# (log line already removed in a previous pass if absent; tolerate both)
if 'Log("group-click ignored (mode off)")\n    if !gGroupMode' in t:
    t = t.replace('Log("group-click ignored (mode off)")\n    if !gGroupMode', '    if !gGroupMode', 1)

io.open(p, 'wb').write(t.encode('utf-8'))
print("normalized + seen-at-entry applied")
