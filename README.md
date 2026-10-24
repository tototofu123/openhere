# OpenHere — apps open where you are

A free, portable, single-file Windows tray utility that **moves every newly opened window to the monitor your mouse cursor is on**. One click to run, auto-starts with Windows if you want, and a tray toggle puts Windows back to 100% stock behavior at any moment.

Built for the 3-monitor life where everything always opened on the wrong screen.

```
   you are here                          window opens there
   ─────────────                         ─────────────────────────────
   cursor on screen 2      ──launch──▶   app appears on screen 2
   click icon on screen 1  ──launch──▶   app appears on screen 1
   tray icon ⏸ (paused)    ──launch──▶   stock Windows behavior
```

## Quick start

1. Install [AutoHotkey v2](https://www.autohotkey.com/) once:
   `winget install AutoHotkey.AutoHotkey`
2. Download `OpenHere.ahk` (or clone this repo) and double-click it. That's the whole install.
3. Optional: right-click the tray icon → **Run at startup**.

Requirements: Windows 10/11. No admin rights. Nothing is installed and no system setting is touched — deleting the file removes OpenHere entirely.

## What it does

- **Follows the cursor** — a new app window lands on the monitor your mouse is on, centered in the work area. Desktop-icon launches, Start-menu launches, pinned-taskbar launches, folder windows — all covered.
- **Preserves state** — maximized windows re-maximize on the target monitor; fullscreen borderless windows are moved whole; owned dialogs (Save As…) keep following their parent app.
- **Fights back gracefully** — apps that restore their own saved geometry on startup (browsers, Office) get re-asserted a few times, then OpenHere concedes and you can pin them with a rule.
- **Respects the shell** — taskbar, Start, search, Action Center, IME and XAML content-island ghosts are never touched.

### Tray menu

| Item | What it does |
|---|---|
| **Enabled** ✓ | Master switch. Unchecked = OpenHere does nothing at all; Windows behaves exactly stock. |
| **Run at startup** | Creates/removes a shortcut in your Startup folder. |
| **Edit rules…** | Opens `openhere.ini` next to the script. |
| **Reload rules** | Re-reads the config without restarting. |
| **Quit** | Fully exits. |

### Config (`openhere.ini`, auto-created on first run)

```ini
[general]
enabled=1              ; the tray toggle writes here
placement=center       ; center | remember_relative (planned)

[rules]
; per-app rules win over the global behavior:
;   never        = this app keeps Windows' own placement memory
;   cursor       = follow the cursor (the default anyway)
;   monitor:N    = pin this app to monitor N (1-based, Windows display settings order)
; vlc.exe=never
; obs64.exe=monitor:2
```

The override model is layered on purpose: **on** = OpenHere intercepts new windows before Windows' default placement matters; **paused** = literally no code runs; **per-app rules** = Windows' own per-app memory wins for that app. No Windows setting is ever modified — there is nothing to undo.

## How it works, in one breath

Windows tells us when a top-level window shows (`SetWinEventHook`, `EVENT_OBJECT_SHOW`). We check the window is real — top-level, visible, unowned, not cloaked (`DWMWA_CLOAKED`), not a tool window, not shell/UI-island plumbing — find the cursor's monitor (`MonitorFromPoint`), and quietly `SetWindowPos` (no activation, no z-order change) into that monitor's work area. The whole script runs per-monitor-DPI-aware, which is what makes mixed-scale monitor setups land correctly.

Two filters proved load-bearing during testing: cloaked-ghost filtering (modern Windows creates invisible UWP/XAML windows constantly) and a deferred title check (Win11 Notepad shows its window before setting its title, so it gets one 400 ms retry instead of being rejected).

## Testing

`tests/` contains a PowerShell harness that places the cursor on a chosen monitor (geometry-based, since `EnumDisplayMonitors` order is not stable), launches an app, and asserts which monitor the new window landed on:

```
Test A  notepad follows cursor to each monitor .............. PASS
Test B1 rule notepad.exe=monitor:1 pins while cursor elsewhere  PASS
Test B2 rule notepad.exe=never respected ..................... PASS
Test B3 enabled=0 — stock Windows, untouched ................. PASS
Test C  explorer folder window (CabinetWClass) follows ....... PASS
```

Visual verification was done with per-monitor screenshots. Known benign quirk: Win11 Notepad spawns a few internal host windows (class `Notepad`) at startup that follow along invisibly — they land on the same monitor as the real window and are never seen.

## Known limitations

- The `Win+S` search panel is shell UI (`SearchHost.exe`) and is deliberately excluded in v0.1. Tip: on Windows 11 the search panel opens on whichever monitor's taskbar you click it from — use the taskbar search box on the screen you want.
- Apps launched **minimized** are left alone.
- `remember_relative` placement is designed but not implemented (`center` is always used for now).
- A standalone `OpenHere.exe` (via Ahk2Exe) is planned for v0.2 — the compiler's CLI mode currently misbehaves on the dev machine, so v0.1 ships as a script, which AutoHotkey runs natively with one click.

## Roadmap

- **v0.2** — compiled single-exe distribution, GitHub Release download, icon.
- **v0.3** — `remember_relative` placement, a "fights back" hint writer, optional debug GUI.
- **someday** — experimental shell-surface following (Start/search), auto-update check.

## Origin

This is [idea 032](https://github.com/tototofu123/ideas) — *"the window goes to the human, not the human to the window."* The only existing tool with this exact behavior is a paid feature (DisplayFusion Pro's Triggers); the free options cover slices of it (FancyZones, Open-Shell). OpenHere is the small, free, maintained thing that does exactly one job.

## License

MIT — see [LICENSE](LICENSE).
