@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..") do set "ROOT_DIR=%%~fI"
set "UV_BIN=%ROOT_DIR%\program\exe\uv\uv.exe"

if not exist "%UV_BIN%" (
  echo [ERROR] Missing bundled uv: %UV_BIN%
  exit /b 1
)

set "FORWARD_ARGS=setup"
:collect_args
if "%~1"=="" goto launch
set "FORWARD_ARGS=!FORWARD_ARGS! "%~1""
shift
goto collect_args

:launch
call "%UV_BIN%" run --python 3.12 --no-project python "%ROOT_DIR%\quickserver.py" !FORWARD_ARGS!
exit /b %ERRORLEVEL%
