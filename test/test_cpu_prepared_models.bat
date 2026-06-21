@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "RESULT_FILE=%~1"
echo [INFO] Compatibility wrapper -> test\cases\case_cpu_prepared_models.bat
call "%SCRIPT_DIR%cases\case_cpu_prepared_models.bat" "%RESULT_FILE%"
exit /b %ERRORLEVEL%
