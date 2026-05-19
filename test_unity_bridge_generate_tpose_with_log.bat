@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%test_unity_bridge_generate_tpose_with_log.ps1" %*
exit /b %ERRORLEVEL%
