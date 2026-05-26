@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%test_recovery_matrix_serial.bat" %*
exit /b %ERRORLEVEL%
