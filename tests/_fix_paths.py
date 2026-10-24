import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

# TrayIconPath: corrupted by a BEL character (\a python escape eaten earlier)
bad_tray = 'for c in [A_ScriptDir "\x07ssets\\" name, A_ScriptDir "\\..\x07ssets\\" name]'
good_tray = 'for c in [A_ScriptDir "\\assets\\" name, A_ScriptDir "\\..\\assets\\" name]'
assert t.count(bad_tray) == 1, "tray anchor"
t = t.replace(bad_tray, good_tray)

# DesktopIconPath: drop the two broken candidates, keep the working one
bad_desk = 'for c in [A_ScriptDir "\\assets\\" name, A_ScriptDir "\\..\\" name, A_ScriptDir "\\..\\assets\\" name]'
good_desk = 'for c in [A_ScriptDir "\\assets\\" name, A_ScriptDir "\\..\\assets\\" name]'
assert t.count(bad_desk) == 1, "desktop anchor"
t = t.replace(bad_desk, good_desk)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("paths fixed")
