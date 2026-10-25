# Close PCL once the method-1 block appears in its log, or at the deadline.
# ASCII only. Windows PowerShell 5.1 compatible.

param(
    [string]$PclDir,
    [int]$MaxSeconds = 35
)

$deadline = (Get-Date).AddSeconds($MaxSeconds)
$proc = $null

while ((Get-Date) -lt $deadline) {
    $proc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Plain*' -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($proc) { break }
    Start-Sleep -Milliseconds 300
}
if (-not $proc) { exit 1 }

$logDir = Join-Path $PclDir 'PCL'
while ((Get-Date) -lt $deadline) {
    $log = Get-ChildItem -Path $logDir -Filter 'Log*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($log) {
        $hit = Select-String -LiteralPath $log.FullName -Pattern 'LaunchAdvanceRun' -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) {
            Start-Sleep -Seconds 1
            break
        }
    }
    Start-Sleep -Milliseconds 300
}

try { $proc.CloseMainWindow() | Out-Null } catch { }
if (-not $proc.WaitForExit(6000)) {
    try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch { }
}
