@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "BASE_TEST=%SCRIPT_DIR%\test_unity_bridge_generate_tpose.bat"
if not exist "%BASE_TEST%" (
  echo [ERROR] Base test not found: %BASE_TEST%
  exit /b 1
)

set "KIMODO_TPOSE_OUTPUT=file"
call "%BASE_TEST%"
exit /b %ERRORLEVEL%

