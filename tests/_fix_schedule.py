import io

p = r"C:\Users\totot\Documents\antigravity_projects\openhere\src\OpenHere.ahk"
t = io.open(p, encoding='utf-8').read()

# 1. de-escalating re-assert schedule: 6 attempts over ~8s
old = """ScheduleReassert(hwnd, targetMon, attempt, desired) {
    QueueDeferred(hwnd, "reassert", targetMon, attempt, desired, 500)
}"""
new = """ScheduleReassert(hwnd, targetMon, attempt, desired) {
    ; de-escalating: 400ms, 600ms, 900ms, 1.4s, 2s, 2.8s — slow-restoring
    ; apps (Windows Terminal restores its own geometry late) get held too
    static delays := [400, 600, 900, 1400, 2000, 2800]
    idx := Max(1, Min(delays.Length, delays.Length - attempt + 1))
    QueueDeferred(hwnd, "reassert", targetMon, attempt, desired, delays[idx])
}"""
assert t.count(old) == 1, "schedule"
t = t.replace(old, new)

# 2. initial attempt count 5 -> 6 (SnapActiveWindow too)
old = "        ScheduleReassert(hwnd, targetMon, 5, desired)"
new = "        ScheduleReassert(hwnd, targetMon, 6, desired)"
assert t.count(old) == 1, "handlewindow"
t = t.replace(old, new)
old = "                ScheduleReassert(hwnd, mon, 5, {l: cell.l, t: cell.t, r: cell.r, b: cell.b})"
new = "                ScheduleReassert(hwnd, mon, 6, {l: cell.l, t: cell.t, r: cell.r, b: cell.b})"
assert t.count(old) == 1, "snapactive"
t = t.replace(old, new)

io.open(p, 'w', encoding='utf-8', newline='\n').write(t)
print("re-assert schedule extended")
