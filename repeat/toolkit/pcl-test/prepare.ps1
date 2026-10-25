# First-logon preparation for the PCL PoC demo VM.
# ASCII only. Runs elevated in the interactive desktop session.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Ev = Join-Path $Root 'evidence'
New-Item -ItemType Directory -Force -Path $Ev | Out-Null

try { Start-Transcript -Path (Join-Path $Ev 'prepare-transcript.txt') -Append | Out-Null } catch { }

function Log([string]$Message) {
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    Write-Host $line
    try { Add-Content -LiteralPath (Join-Path $Ev 'prepare.log') -Value $line -Encoding UTF8 } catch { }
}

try {
    Log 'prepare: waiting for Explorer / desktop'
    for ($i = 0; $i -lt 90; $i++) {
        if (Get-Process explorer -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Seconds 1
    }
    Start-Sleep -Seconds 8

    Log 'prepare: EULA / notice bookkeeping'
    & reg.exe add 'HKCU\Software\PCL' /v SystemEulaVersion /t REG_SZ /d 2 /f | Out-Null
    & reg.exe add 'HKCU\Software\PCL' /v HintNotice /t REG_SZ /d 0 /f | Out-Null

    Log 'prepare: disable toast notifications and tips'
    & reg.exe add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications' /v ToastEnabled /t REG_DWORD /d 0 /f | Out-Null
    & reg.exe add 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' /v SubscribedContent-338389Enabled /t REG_DWORD /d 0 /f | Out-Null

    Log 'prepare: power settings'
    & powercfg.exe /change monitor-timeout-ac 0 | Out-Null
    & powercfg.exe /change standby-timeout-ac 0 | Out-Null
    & powercfg.exe /change hibernate-timeout-ac 0 | Out-Null

    Log 'prepare: defender exclusions'
    try {
        Add-MpPreference -ExclusionPath @('C:\PCLPoC', (Join-Path $env:USERPROFILE 'Desktop\PCL'), 'C:\Users\Public') -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    } catch {
        Log ('prepare: defender exclusion warning: ' + $_.Exception.Message)
    }

    Log 'prepare: copy PoC toolkit to C:\PCLPoC'
    if (Test-Path -LiteralPath 'C:\PCLPoC') {
        Remove-Item -LiteralPath 'C:\PCLPoC' -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath (Join-Path $Root 'PCLPoC') -Destination 'C:\PCLPoC' -Recurse -Force

    Log 'prepare: create retry wrapper and scheduled task'
    $retry = @'
@echo off
for %%d in (C D E F G H I J K) do (
  if exist "%%d:\pcl-test\retry.flag" (
    del "%%d:\pcl-test\retry.flag" >nul 2>&1
    call "%%d:\pcl-test\firstlogon.cmd"
    exit /b 0
  )
)
exit /b 0
'@
    try {
        Set-Content -LiteralPath 'C:\pcl-retry.cmd' -Value $retry -Encoding ASCII
        try {
            $taskName = 'PCLPoCRetry'
            $user = $env:COMPUTERNAME + '\' + $env:USERNAME
            $action = New-ScheduledTaskAction -Execute 'C:\pcl-retry.cmd'
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
            Log 'prepare: scheduled task registered'
        } catch {
            Log ('prepare: scheduled task warning: ' + $_.Exception.Message)
        }
    } catch {
        Log ('prepare: retry wrapper warning: ' + $_.Exception.Message)
    }

    Log 'prepare: starting demo.ps1'
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'demo.ps1')) -WindowStyle Normal
    Log 'prepare: done'
} catch {
    Log ('prepare: ERROR ' + $_.Exception.Message)
    try {
        Add-Content -LiteralPath (Join-Path $Ev 'prepare-error.txt') -Value $_.Exception.ToString() -Encoding UTF8
    } catch { }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
