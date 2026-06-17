@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\download_model.ps1" %*
set "RC=%ERRORLEVEL%"
exit /b %RC%
