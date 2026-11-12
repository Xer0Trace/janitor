@echo off
setlocal
set "JANITOR_SCRIPT=%~dp0janitor.ps1"
set "JANITOR_PREVIEW="
if /i "%~1"=="-Preview" set "JANITOR_PREVIEW=1"
if /i "%~1"=="-WhatIf" set "JANITOR_PREVIEW=1"
if not "%~1"=="" if not defined JANITOR_PREVIEW goto usage
if not "%~2"=="" goto usage

set "JANITOR_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "JANITOR_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%JANITOR_POWERSHELL%" -NoLogo -NoProfile -Command "$ErrorActionPreference = 'Stop'; $janitor = [scriptblock]::Create((Get-Content -LiteralPath $env:JANITOR_SCRIPT -Raw)); if ($env:JANITOR_PREVIEW) { & $janitor -Preview } else { & $janitor }"
set "JANITOR_EXIT=%ERRORLEVEL%"
if not defined JANITOR_PREVIEW pause
exit /b %JANITOR_EXIT%

:usage
echo Usage: Run-Janitor.cmd [-Preview ^| -WhatIf]
exit /b 2
