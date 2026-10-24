Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | ForEach-Object {
    "pid $($_.ProcessId): $($_.CommandLine)"
}
if (-not (Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'")) {
    "NO AutoHotkey64 process running"
}
