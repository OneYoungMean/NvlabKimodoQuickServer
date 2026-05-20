@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
call "%SCRIPT_DIR%test_unity_bridge_generate_tpose_impl.bat" %*
exit /b %ERRORLEVEL%
