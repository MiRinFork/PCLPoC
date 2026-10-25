@echo off
setlocal
set "HERE=%~dp0"
if not exist "%HERE%evidence" mkdir "%HERE%evidence"
echo %DATE% %TIME% firstlogon >> "%HERE%evidence\firstlogon.txt"
start "PCL-PoC-Prepare" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%HERE%prepare.ps1"
exit /b 0
