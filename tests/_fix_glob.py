import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

old = '''TrayIconPath(on) {
    name := on ? "tray-on.ico" : "tray-off.ico"
    for c in [A_ScriptDir "\\assets\\" name, A_ScriptDir "\\..\\assets\\" name]
        if FileExist(c)
            return c
    return ""
}'''
new = '''TrayIconPath(on) {
    return LatestIcon(on ? "tray-on-" : "tray-off-")
}'''
assert t.count(old) == 1, "tray block"
t = t.replace(old, new)

old = '''DesktopIconPath(on) {
    name := on ? "desktop-on.ico" : "desktop-off.ico"
    for c in [A_ScriptDir "\\assets\\" name, A_ScriptDir "\\..\\assets\\" name]
        if FileExist(c)
            return c
    return ""
}'''
new = '''DesktopIconPath(on) {
    return LatestIcon(on ? "desktop-on-" : "desktop-off-")
}'''
assert t.count(old) == 1, "desktop block"
t = t.replace(old, new)

helper = '''; icons are hash-versioned by the generator — glob for the newest so the
; shell icon cache can never serve a stale render
LatestIcon(prefix) {
    best := ""
    bestTime := 0
    for dir in [A_ScriptDir "\\assets\\", A_ScriptDir "\\..\\assets\\"]
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

UpdateTrayIcon() {'''
old = '''UpdateTrayIcon() {'''
assert t.count(old) == 1, "helper insert"
t = t.replace(old, helper)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("glob resolution wired")
