import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

# 1. EnsureDesktopShortcut: the wantArgs line has a literal TAB ("\toggle" eaten to TAB+oggle)
bad = '        wantArgs := \'"\' A_ScriptDir "\toggle.ahk" \'"\'' + '\n'
good = '        wantArgs := \'"\' A_ScriptDir "\\toggle.ahk" \'"\'' + '\n'
assert t.count(bad) == 1, "wantArgs anchor"
t = t.replace(bad, good)

# 2. WriteToggleHelper: FileAppend has no Overwrite option — use FileOpen "w"
old = '    FileAppend(content, helper, "Overwrite")\n'
new = '''    f := FileOpen(helper, "w")
    f.Write(content)
    f.Close()
'''
assert t.count(old) == 1, "FileAppend anchor"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("both fixed")
