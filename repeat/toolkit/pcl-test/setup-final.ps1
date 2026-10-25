# Run once, elevated, on the installed lab VM.
# Configures 100% DPI, UAC off, lab PoC files, and a disabled logon task.
# The logon task is enabled manually just before the final recorded boot.

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Ev = Join-Path $Root 'evidence'
New-Item -ItemType Directory -Force -Path $Ev | Out-Null

try { Start-Transcript -Path (Join-Path $Ev 'setup-final.txt') -Append | Out-Null } catch { }

function Log([string]$Message) {
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $Message
    Write-Host $line
    try { Add-Content -LiteralPath (Join-Path $Ev 'setup-final.log') -Value $line -Encoding UTF8 } catch { }
}

try {
    Log 'setup-final: timezone'
    & tzutil.exe /s 'China Standard Time' | Out-Null

    Log 'setup-final: 100% DPI'
    & reg.exe add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f | Out-Null
    & reg.exe add 'HKCU\Control Panel\Desktop' /v Win8DpiScaling /t REG_DWORD /d 0 /f | Out-Null
    & reg.exe add 'HKCU\Control Panel\Desktop' /v DesktopDPIOverride /t REG_SZ /d 0 /f | Out-Null

    Log 'setup-final: UAC off'
    & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v EnableLUA /t REG_DWORD /d 0 /f | Out-Null
    & reg.exe add 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f | Out-Null

    Log 'setup-final: PCL EULA bookkeeping'
    & reg.exe add 'HKCU\Software\PCL' /v SystemEulaVersion /t REG_SZ /d 2 /f | Out-Null
    & reg.exe add 'HKCU\Software\PCL' /v HintNotice /t REG_SZ /d 0 /f | Out-Null

    Log 'setup-final: defender exclusions'
    try {
        Add-MpPreference -ExclusionPath @('C:\PCLPoC', (Join-Path $env:USERPROFILE 'Desktop\PCL'), 'C:\Users\Public') -ErrorAction SilentlyContinue
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
    } catch {
        Log ('setup-final: defender warning: ' + $_.Exception.Message)
    }

    Log 'setup-final: copy PoC to C:\PCLPoC'
    if (Test-Path -LiteralPath 'C:\PCLPoC') {
        Remove-Item -LiteralPath 'C:\PCLPoC' -Recurse -Force -ErrorAction SilentlyContinue
    }
    Copy-Item -LiteralPath (Join-Path $Root 'PCLPoC') -Destination 'C:\PCLPoC' -Recurse -Force

    Log 'setup-final: remove old retry task / startup entry'
    Unregister-ScheduledTask -TaskName 'PCLPoCRetry' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\PCLDemo.cmd'
    Remove-Item -LiteralPath $startup -Force -ErrorAction SilentlyContinue

    Log 'setup-final: create C:\pcl-demo.cmd'
    $wrapper = @'
@echo off
for %%d in (C D E F G H I J K) do (
  if exist "%%d:\pcl-test\demo.ps1" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%%d:\pcl-test\demo.ps1"
    exit /b 0
  )
)
'@
    Set-Content -LiteralPath 'C:\pcl-demo.cmd' -Value $wrapper -Encoding ASCII

    Log 'setup-final: register disabled logon task'
    $user = $env:COMPUTERNAME + '\' + $env:USERNAME
    $action = New-ScheduledTaskAction -Execute 'C:\pcl-demo.cmd'
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName 'PCLPoCDemo' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Disable-ScheduledTask -TaskName 'PCLPoCDemo' | Out-Null

    Log 'setup-final: done; rebooting'
} catch {
    Log ('setup-final: ERROR ' + $_.Exception.Message)
    try { Add-Content -LiteralPath (Join-Path $Ev 'setup-final-error.txt') -Value $_.Exception.ToString() -Encoding UTF8 } catch { }
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}

& shutdown.exe /r /t 8 /c 'PCL PoC final setup'
