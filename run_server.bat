@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "UV_BIN=%ROOT_DIR%\program\exe\uv\uv.exe"

if not exist "%UV_BIN%" (
  echo [ERROR] Missing bundled uv: %UV_BIN%
  exit /b 1
)

set "ARGS="
:collect_args
if "%~1"=="" goto launch
set "NEXT=%~1"
if defined ARGS (
  set "ARGS=!ARGS! "!NEXT!""
) else (
  set "ARGS="!NEXT!""
)
shift
goto collect_args

:launch
set "CMD=%UV_BIN% run --python 3.12 --no-project python quickserver.py !ARGS!"
call %CMD%
exit /b %ERRORLEVEL%
