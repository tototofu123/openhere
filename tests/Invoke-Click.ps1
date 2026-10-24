# Invoke-Click.ps1 — PS-native input: SendKeys for hotkeys, user32 mouse_event for clicks
# args: -Mode group|snap|tidy  -X n -Y n
param(
    [Parameter(Mandatory)][ValidateSet('group', 'snap', 'tidy', 'click', 'esc')][string]$Mode,
    [int]$X = 0,
    [int]$Y = 0
)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win32.ps1")

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class OHInput {
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
}
"@

function Send-Click {
    param([int]$x, [int]$y)
    [OHInput]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 120
    [OHInput]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)   # LEFTDOWN
    Start-Sleep -Milliseconds 60
    [OHInput]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)   # LEFTUP
}

switch ($Mode) {
    'group' {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys('^%g')
        "sent ctrl+alt+g"
    }
    'snap' {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys('^%s')
        "sent ctrl+alt+s"
    }
    'tidy' {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys('^%t')
        "sent ctrl+alt+t"
    }
    'esc' {
        $wsh = New-Object -ComObject WScript.Shell
        $wsh.SendKeys('{ESC}')
        "sent esc"
    }
    'click' {
        Send-Click $X $Y
        "clicked $X,$Y"
    }
}
