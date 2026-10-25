# Keep the demo terminal on the left and PCL/calc on the right.
# ASCII only. Windows PowerShell 5.1 compatible.

param(
    [long]$ConsoleHwnd,
    [int]$X,
    [int]$Y,
    [int]$W,
    [int]$H,
    [int]$PclX,
    [int]$PclW,
    [int]$Minutes = 20
)

. (Join-Path $PSScriptRoot 'lib-gui.ps1')

if ($ConsoleHwnd -ne 0) {
    [PclGui]::Move([IntPtr]$ConsoleHwnd, $X, $Y, $W, $H)
}

$end = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $end) {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne 0 -and (
            $_.ProcessName -like '*Plain*' -or
            $_.ProcessName -like '*calc*' -or
            $_.ProcessName -like '*Calculator*'
        )
    }
    foreach ($p in $procs) {
        [PclGui]::Move($p.MainWindowHandle, $PclX, 0, $PclW, $H)
    }
    Start-Sleep -Milliseconds 500
}
