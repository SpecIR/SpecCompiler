@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0specc.ps1" %*
exit /b %errorlevel%
