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
3. It registers itself to launch at Windows startup on first run (per-user Run key, no admin needed). To stop that, right-click the tray icon → **Run at startup** to untick it, or set `run_at_startup=0` in the ini.

Requirements: Windows 10/11. No admin rights. Nothing is installed; the only change outside the folder is an optional per-user Run key for autostart (untick **Run at startup** to remove it).

## What it does

- **Follows the cursor** — a new app window lands on the monitor your mouse is on. Desktop-icon launches, Start-menu launches, pinned-taskbar launches, folder windows — all covered. Windows that were already open before OpenHere started are left exactly where you had them; only genuinely new windows are moved.
- **Snaps into empty space (v0.2)** — OpenHere knows what's already on the monitor and fills the next free slot instead of stacking on top of it:

```
   window on the left half   ->  next window fills the right half
   window on the left third  ->  next window takes the middle third
   window in the top-left 1/4 ->  next takes top-right, then bottom-left
   half + quarter occupied    ->  next fills the remaining quarter
   nothing on the monitor     ->  centered, keeping the app's own size
```

  The grid is detected from the shape of existing windows (work area only — the taskbar is excluded), and per-app rules still win. A window that opens maximized is snapped into the free cell too; a genuinely full or ungridded screen falls back to plain centering. Toggle it any time: tray → **Snap into empty space**, or `placement=snap|center` in the ini.
- **Preserves state** — maximized windows re-maximize on the target monitor; fullscreen borderless windows are moved whole; owned dialogs (Save As…) keep following their parent app.
- **Fights back gracefully** — apps that restore their own saved geometry on startup (browsers, Office) get re-asserted a few times, then OpenHere concedes and you can pin them with a rule.
- **Respects the shell** — taskbar, Start, search, Action Center, IME and XAML content-island ghosts are never touched.

The tray icon is OpenHere itself: **left-click it to pause/resume**. The state color is shared everywhere — **green = on, red = off** — on the tray icon and on the `OpenHere.lnk` desktop shortcut (created on first run, launching the app; its icon swaps files on every toggle so the color is always current). Right-click the tray icon for the full menu.

## Grouping (v0.3)

Press **Ctrl+Alt+G** to enter grouping mode: click the windows you want to group (a translucent highlight marks the selection, click again to unselect), then press **Ctrl+Alt+G** again to confirm. The members stack into one cell — unsnapped ones get snapped by construction — with a floating **tab bar** across the top of the cell: click a tab to switch windows, arrows appear when there are more tabs than fit (10+ on a half-cell, titles truncated), and the bar is only visible while a member of the group is the foreground window. Groups dissolve automatically when their last window closes. Esc cancels grouping mode.

The vocabulary is borrowed from [agent-bus](https://github.com/tototofu123/agent-bus): a group is a *room*, members join by clicking, and one member is the *speaker*. `mode=minimize` in the ini makes the previous speaker minimize on switch instead of stacking.

Two more hotkeys:

| Hotkey | Action |
|---|---|
| **Ctrl+Alt+O** | Enable/disable the whole app (same as the tray toggle) |
| **Ctrl+Alt+S** | Snap the active window into the next free cell of its monitor |
| **Ctrl+Alt+T** | Flush drifted grid windows on the current monitor into place |

### Protected monitors (v0.4)

New windows are never snapped onto a monitor that is already fully occupied:

- a **fullscreen or maximized** window covering ~95%+ of the monitor protects it;
- a **media player** (VLC, mpv, Media Player, Spotify…) covering 70%+ of a monitor protects it — your video never gets buried;
- if **every** monitor is protected, new windows are simply left where Windows puts them.

Extra media process names can be added under `[media]` in the ini. Browsers playing windowed video can't be detected (no reliable signal) — fullscreen video in a browser is covered by the fullscreen rule.

Hotkeys are configurable in `[grouping]` of the ini (`^` = Ctrl, `!` = Alt, `+` = Shift).

### Tray menu

| Item | What it does |
|---|---|
| **Enabled** ✓ | Master switch. Unchecked = OpenHere does nothing at all; Windows behaves exactly stock. |
| **Run at startup** | Adds/removes the per-user Run-key entry that launches OpenHere with Windows (on by default). |
| **Edit rules…** | Opens `openhere.ini` next to the script. |
| **Reload rules** | Re-reads the config without restarting. |
| **Quit** | Fully exits. |

### Config (`openhere.ini`, auto-created on first run)

```ini
[general]
enabled=1              ; the tray toggle writes here
placement=snap         ; snap = fill the next free slot | center = always center
run_at_startup=1       ; register a per-user Run key so OpenHere starts with Windows

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
- With a maximized window covering the monitor there is no free cell to fill, so new windows are centered — close or unmaximize the big one and snapping resumes.
- A standalone `OpenHere.exe` (via Ahk2Exe) is still pending — the compiler's CLI mode misbehaves on the dev machine, so OpenHere ships as a script, which AutoHotkey runs natively with one click.

## Roadmap

- **v0.4** — compiled single-exe distribution, GitHub Release download, icon.
- **later** — per-group persistence across restarts, drag-to-reorder tabs, per-monitor snap-style presets, experimental shell-surface following (Start/search).

## Origin

This is [idea 032](https://github.com/tototofu123/ideas) — *"the window goes to the human, not the human to the window."* The only existing tool with this exact behavior is a paid feature (DisplayFusion Pro's Triggers); the free options cover slices of it (FancyZones, Open-Shell). OpenHere is the small, free, maintained thing that does exactly one job.

## License

MIT — see [LICENSE](LICENSE).
