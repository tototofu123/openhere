#Requires AutoHotkey v2.0
#SingleInstance Off
DetectHiddenWindows true
if WinExist("OpenHere.ahk ahk_class AutoHotkey")
    PostMessage 0x404, 0, 0x202
else
    Run "C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
