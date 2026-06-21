@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "RESULT_FILE=%~1"
echo [INFO] Compatibility wrapper -> test\cases\case_cpu_from_scratch.bat
call "%SCRIPT_DIR%cases\case_cpu_from_scratch.bat" "%RESULT_FILE%"
exit /b %ERRORLEVEL%
