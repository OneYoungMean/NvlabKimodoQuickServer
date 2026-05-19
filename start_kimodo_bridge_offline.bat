@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%start_kimodo_bridge_offline.ps1" %*
exit /b %ERRORLEVEL%
