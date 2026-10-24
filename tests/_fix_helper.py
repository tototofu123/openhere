import io
import re

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

correct = r'''WriteToggleHelper() {
    global
    helper := A_ScriptDir "\toggle.ahk"
    q := Chr(34)   ; the quote character — no escaped-quote spaghetti
    lines := []
    lines.Push("#Requires AutoHotkey v2.0")
    lines.Push("#SingleInstance Off")
    lines.Push("DetectHiddenWindows true")
    lines.Push("if WinExist(" q A_ScriptName " ahk_class AutoHotkey)")
    lines.Push("    PostMessage 0x404, 0, 0x202")
    lines.Push("else")
    lines.Push("    Run " q A_ScriptFullPath q)
    content := ""
    for ln in lines
        content .= ln "`n"
    if !FileExist(helper) || (FileRead(helper) != content)
        FileDelete(helper)
    FileAppend(content, helper)
    Log("toggle helper written")
}'''

m = re.search(r"WriteToggleHelper\(\) \{.*?\n\}", t, re.S)
assert m, "function not found"
t = t[:m.start()] + correct + t[m.end():]
io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("WriteToggleHelper rebuilt with Chr(34)")
