# Copy the silent-update staging exe and its provenance before PCL cleanup.
# ASCII only. Windows PowerShell 5.1 compatible.

param(
    [string]$Staging,
    [string]$Evidence,
    [string]$PclDir,
    [int]$Timeout = 180
)

if (-not $Staging -and $PclDir) {
    $Staging = Join-Path $PclDir 'PCL\Plain Craft Launcher 2.exe'
}
if (-not $Staging) { exit 2 }

$deadline = (Get-Date).AddSeconds($Timeout)
$last = -1

while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $Staging) {
        $len = (Get-Item -LiteralPath $Staging).Length
        if ($len -gt 0 -and $len -eq $last) {
            Copy-Item -LiteralPath $Staging -Destination (Join-Path $Evidence 'staging.exe') -Force
            (Get-FileHash -LiteralPath $Staging -Algorithm SHA256).Hash | Set-Content -LiteralPath (Join-Path $Evidence 'staging.sha256.txt') -Encoding ASCII
            if ($PclDir) {
                Copy-Item -Path (Join-Path $PclDir 'PCL\Log*.txt') -Destination $Evidence -Force -ErrorAction SilentlyContinue
                Copy-Item -LiteralPath (Join-Path $PclDir 'PCL\Setup.ini') -Destination $Evidence -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -Path (Join-Path $env:TEMP 'PCL\Cache\*') -Destination $Evidence -Force -ErrorAction SilentlyContinue
            'FOUND' | Set-Content -LiteralPath (Join-Path $Evidence 'watch-staging.txt') -Encoding ASCII
            exit 0
        }
        $last = $len
    }
    Start-Sleep -Milliseconds 250
}

'TIMEOUT' | Set-Content -LiteralPath (Join-Path $Evidence 'watch-staging.txt') -Encoding ASCII
exit 1
