@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
echo [INFO] Deprecated compatibility wrapper: forwarding to serial recovery matrix.
call "%SCRIPT_DIR%test_recovery_matrix_serial.bat" %*
exit /b %ERRORLEVEL%
