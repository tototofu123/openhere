#Requires AutoHotkey v2.0
CoordMode "Mouse", "Screen"
; grouping-driver.ahk — simulates user input for the grouping test
; args: x1 y1 x2 y2 [tabX tabY]
x1 := Integer(A_Args[1])
y1 := Integer(A_Args[2])
x2 := Integer(A_Args[3])
y2 := Integer(A_Args[4])
tx := A_Args.Length >= 5 ? Integer(A_Args[5]) : 0
ty := A_Args.Length >= 6 ? Integer(A_Args[6]) : 0

Send "^!g"                       ; grouping mode ON
Sleep 600
MouseClick "left", x1, y1        ; select window A
Sleep 400
MouseClick "left", x2, y2        ; select window B
Sleep 400
Send "^!g"                       ; confirm -> group created
Sleep 900
if (tx)
    MouseClick "left", tx, ty    ; click tab #1 -> activate member A
