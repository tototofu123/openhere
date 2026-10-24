# win32.ps1 — shared Win32 helpers for OpenHere tests
# Dot-source this file:  . .\win32.ps1

if (-not ("OpenHereWin32" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class OpenHereWin32 {
    public delegate bool MonitorEnumProc(IntPtr hMon, IntPtr hdc, ref RECT rect, IntPtr data);
    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lparam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int L, T, R, B; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint cmd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lparam);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr wparam, IntPtr lparam);

    public const uint MONITOR_DEFAULTTONEAREST = 2;
    public const uint GW_OWNER = 4;

    public static List<RECT> MonitorRects = new List<RECT>();
    public static List<IntPtr> MonitorHandles = new List<IntPtr>();
    public static IntPtr PrimaryHandle = IntPtr.Zero;

    public static bool OnMonitor(IntPtr hMon, IntPtr hdc, ref RECT r, IntPtr data) {
        MonitorRects.Add(r);
        MonitorHandles.Add(hMon);
        return true;
    }

    public static void EnumMonitors() {
        MonitorRects.Clear();
        MonitorHandles.Clear();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, OnMonitor, IntPtr.Zero);
        // MONITORINFO to find primary
        for (int i = 0; i < MonitorHandles.Count; i++) {
            MONITORINFO mi = new MONITORINFO();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
            if (GetMonitorInfo(MonitorHandles[i], ref mi) && (mi.dwFlags & 1) != 0)
                PrimaryHandle = MonitorHandles[i];
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern bool GetMonitorInfo(IntPtr hMon, ref MONITORINFO mi);

    public static List<IntPtr> TopLevelWindows() {
        List<IntPtr> result = new List<IntPtr>();
        EnumWindows((hwnd, lp) => { result.Add(hwnd); return true; }, IntPtr.Zero);
        return result;
    }

    public static string ClassName(IntPtr hwnd) {
        var sb = new System.Text.StringBuilder(256);
        GetClassName(hwnd, sb, 256);
        return sb.ToString();
    }

    public static string ProcessNameOf(IntPtr hwnd) {
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        if (pid == 0) return "";
        try {
            var p = System.Diagnostics.Process.GetProcessById((int)pid);
            return p.ProcessName;
        } catch { return ""; }
    }

    public static bool IsRealAppWindow(IntPtr hwnd) {
        if (!IsWindowVisible(hwnd)) return false;
        if (GetWindowTextLength(hwnd) == 0) return false;
        if (GetWindow(hwnd, GW_OWNER) != IntPtr.Zero) return false;
        return true;
    }
}
"@
    [OpenHereWin32]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
    [OpenHereWin32]::EnumMonitors()
}

function Get-MonitorList {
    $list = @()
    for ($i = 0; $i -lt [OpenHereWin32]::MonitorRects.Count; $i++) {
        $r = [OpenHereWin32]::MonitorRects[$i]
        $list += [pscustomobject]@{
            Index   = $i + 1
            Handle  = [OpenHereWin32]::MonitorHandles[$i]
            Left    = $r.L; Top = $r.T; Right = $r.R; Bottom = $r.B
            Width   = $r.R - $r.L; Height = $r.B - $r.T
            Primary = ([OpenHereWin32]::MonitorHandles[$i] -eq [OpenHereWin32]::PrimaryHandle)
        }
    }
    return $list
}

function Set-CursorToMonitor {
    param([int]$Index)   # 1-based, per Get-MonitorList order
    $m = Get-MonitorList | Where-Object Index -eq $Index
    if (-not $m) { throw "monitor index $Index not found" }
    $cx = $m.Left + [int]($m.Width / 2)
    $cy = $m.Top + [int]($m.Height / 2)
    [OpenHereWin32]::SetCursorPos($cx, $cy) | Out-Null
    Start-Sleep -Milliseconds 150
    return [pscustomobject]@{ X = $cx; Y = $cy; Monitor = $Index }
}

function Get-CursorPoint {
    $p = New-Object OpenHereWin32+POINT
    [OpenHereWin32]::GetCursorPos([ref]$p) | Out-Null
    return $p
}

# Snapshot of candidate app windows (visible, titled, unowned)
function Get-WindowSnapshot {
    $set = @{}
    foreach ($h in [OpenHereWin32]::TopLevelWindows()) {
        if ([OpenHereWin32]::IsRealAppWindow($h)) { $set[$h.ToInt64()] = $true }
    }
    return $set
}

# Find the NEW window of a process (optionally by class) that was not in $before
function Find-NewWindow {
    param([string]$ProcessName, [string]$Class = "", $before = @{})
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        foreach ($h in [OpenHereWin32]::TopLevelWindows()) {
            if ($before.ContainsKey($h.ToInt64())) { continue }
            if (-not [OpenHereWin32]::IsRealAppWindow($h)) { continue }
            if ($ProcessName -and ([OpenHereWin32]::ProcessNameOf($h) -ine $ProcessName)) { continue }
            if ($Class -and ([OpenHereWin32]::ClassName($h) -ine $Class)) { continue }
            return $h
        }
        Start-Sleep -Milliseconds 150
    }
    return [IntPtr]::Zero
}

function Get-WindowMonitor {
    param([IntPtr]$Hwnd)
    $hMon = [OpenHereWin32]::MonitorFromWindow($Hwnd, [OpenHereWin32]::MONITOR_DEFAULTTONEAREST)
    for ($i = 0; $i -lt [OpenHereWin32]::MonitorHandles.Count; $i++) {
        if ([OpenHereWin32]::MonitorHandles[$i] -eq $hMon) { return $i + 1 }
    }
    return 0
}

function Get-PointMonitor {
    param($P)
    $hMon = [OpenHereWin32]::MonitorFromPoint($P, [OpenHereWin32]::MONITOR_DEFAULTTONEAREST)
    for ($i = 0; $i -lt [OpenHereWin32]::MonitorHandles.Count; $i++) {
        if ([OpenHereWin32]::MonitorHandles[$i] -eq $hMon) { return $i + 1 }
    }
    return 0
}

function Close-Window {
    param([IntPtr]$Hwnd)
    [OpenHereWin32]::PostMessage($Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null  # WM_CLOSE
}

function Show-Monitors {
    Get-MonitorList | ForEach-Object {
        "monitor $($_.Index): ($($_.Left),$($_.Top))-($($_.Right),$($_.Bottom)) $($_.Width)x$($_.Height) primary=$($_.Primary)"
    }
}
