<#::: [get-EventLogs.cmd]
@echo off
chcp 65001 >nul
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ScriptDir='%~dp0'; $code = ([System.IO.File]::ReadAllText('%~f0', [System.Text.Encoding]::UTF8) -split '\r?\n' | Select-Object -Skip 11) -join [Environment]::NewLine; Invoke-Expression $code"
pause

#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$StartTime = (Get-Date).Date.AddDays(-1)

$Channels = @(
    "System",
    "Application",
    "Microsoft-Windows-Dhcp-Client/Admin",
    "Microsoft-Windows-DHCPv6-Client/Admin"
)

$AllLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
Write-Host "[*] Đang quét Windows Event Logs từ $StartTime..." -ForegroundColor Cyan

foreach ($Channel in $Channels) {
    try {
        $Events = Get-WinEvent -FilterHashtable @{
            LogName   = $Channel
            StartTime = $StartTime
            Level     = 1, 2
        } -ErrorAction SilentlyContinue

        foreach ($evt in $Events) {
            $LevelName = switch ($evt.Level) {
                1 { "CRITICAL" }
                2 { "ERROR" }
                3 { "WARNING" }
                default { "INFO" }
            }

            $Msg = if ($evt.Message) { ($evt.Message -split "\r?\n")[0] } else { "[No Description]" }

            $AllLogs.Add([PSCustomObject]@{
                Time     = $evt.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
                Level    = $LevelName
                EventId  = $evt.Id
                Provider = $evt.ProviderName
                Message  = $Msg
            })
        }
    } catch {}
}

$SortedLogs = $AllLogs | Sort-Object Time -Descending
$HtmlPath = Join-Path -Path $ScriptDir -ChildPath "Windows_Errors_Report.html"

$Rows = foreach ($log in $SortedLogs) {
    "      <tr data-level='$($log.Level)'>
        <td class='time-cell'>$($log.Time)</td>
        <td><span class='badge $($log.Level)'>$($log.Level)</span></td>
        <td class='event-id'>#$($log.EventId)</td>
        <td><strong>$([System.Net.WebUtility]::HtmlEncode($log.Provider))</strong></td>
        <td class='msg-cell'>$([System.Net.WebUtility]::HtmlEncode($log.Message))</td>
      </tr>"
}

$HtmlContent = @"
<!DOCTYPE html>
<html lang='vi'>
<head>
  <meta charset='UTF-8'>
  <title>Windows Event Log Report</title>
  <style>
    :root { --bg-color: #0f172a; --card-bg: #1e293b; --border-color: #334155; --text-main: #f8fafc; --text-muted: #94a3b8; }
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: 'Segoe UI', system-ui, sans-serif; }
    body { background-color: var(--bg-color); color: var(--text-main); padding: 24px; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; padding-bottom: 16px; border-bottom: 1px solid var(--border-color); }
    .header h1 { font-size: 22px; color: #38bdf8; }
    .controls { display: flex; gap: 12px; margin-bottom: 20px; }
    .search-box { flex: 1; background: var(--card-bg); border: 1px solid var(--border-color); border-radius: 8px; padding: 10px 16px; color: #fff; outline: none; }
    .filter-btn { background: var(--card-bg); border: 1px solid var(--border-color); color: var(--text-muted); padding: 8px 16px; border-radius: 8px; cursor: pointer; font-weight: 600; }
    .filter-btn.active, .filter-btn:hover { background: #334155; color: #fff; border-color: #38bdf8; }
    .table-container { background: var(--card-bg); border-radius: 12px; border: 1px solid var(--border-color); overflow: hidden; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { background: #0f172a; color: var(--text-muted); padding: 14px 16px; text-align: left; }
    td { padding: 12px 16px; border-bottom: 1px solid var(--border-color); }
    tr:hover { background: #26334d; }
    .badge { padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: 700; }
    .badge.CRITICAL { background: rgba(239,68,68,0.15); color: #f87171; border: 1px solid rgba(239,68,68,0.4); }
    .badge.ERROR { background: rgba(249,115,22,0.15); color: #fb923c; border: 1px solid rgba(249,115,22,0.4); }
    .badge.WARNING { background: rgba(234,179,8,0.15); color: #facc15; border: 1px solid rgba(234,179,8,0.4); }
    .event-id { color: #38bdf8; font-family: monospace; font-weight: 600; }
    .msg-cell { color: #cbd5e1; }
    .time-cell { color: var(--text-muted); font-family: monospace; white-space: nowrap; }
  </style>
</head>
<body>
  <div class='header'>
    <h1>🛡️Windows Event Log Report</h1>
    <div>Tổng số: <strong>$($SortedLogs.Count)</strong> log</div>
  </div>
  <div class='controls'>
    <input type='text' id='searchInput' class='search-box' placeholder='🔍Tìm kiếm...' onkeyup='filterLogs()'>
    <button class='filter-btn active' onclick='setFilter("ALL", this)'>Tất cả</button>
    <button class='filter-btn' onclick='setFilter("CRITICAL", this)'>Critical</button>
    <button class='filter-btn' onclick='setFilter("ERROR", this)'>Error</button>
    <button class='filter-btn' onclick='setFilter("WARNING", this)'>Warning</button>
  </div>
  <div class='table-container'>
    <table id='logTable'>
      <thead>
        <tr><th>Thời gian</th><th>Mức độ</th><th>Event ID</th><th>Provider</th><th>Nội dung (Message)</th></tr>
      </thead>
      <tbody>
$($Rows -join "`n")
      </tbody>
    </table>
  </div>
  <script>
    let currentLevel='ALL';
    function setFilter(lvl, btn){ currentLevel=lvl; document.querySelectorAll('.filter-btn').forEach(b=>b.classList.remove('active')); btn.classList.add('active'); filterLogs(); }
    function filterLogs(){ let s=document.getElementById('searchInput').value.toLowerCase(); document.querySelectorAll('#logTable tbody tr').forEach(r=>{ let lm=(currentLevel==='ALL')||r.getAttribute('data-level')===currentLevel; let tm=r.innerText.toLowerCase().includes(s); r.style.display=(lm&&tm)?'':'none'; }); }
  </script>
</body>
</html>
"@

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($HtmlPath, $HtmlContent, $Utf8NoBom)
Write-Host "[+] Xuất báo cáo thành công: $HtmlPath" -ForegroundColor Green
Start-Process $HtmlPath