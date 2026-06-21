@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "UV_BIN=%ROOT_DIR%\program\exe\uv\uv.exe"
set "VENV_OVERRIDE=%KIMODO_VENV_PATH%"
if not defined VENV_OVERRIDE set "VENV_OVERRIDE=%KIMODO_TEST_VENV_PATH%"

if not exist "%UV_BIN%" (
  echo [ERROR] Missing bundled uv: %UV_BIN%
  exit /b 1
)

set "ARGS="
set "HAS_VENV_ARG="
:collect_args
if "%~1"=="" goto launch
set "NEXT=%~1"
if /I "%NEXT%"=="--venv" set "HAS_VENV_ARG=1"
if defined ARGS (
  set "ARGS=!ARGS! "!NEXT!""
) else (
  set "ARGS="!NEXT!""
)
shift
goto collect_args

:launch
if defined VENV_OVERRIDE if not defined HAS_VENV_ARG (
  if defined ARGS (
    set "ARGS=!ARGS! "--venv" "%VENV_OVERRIDE%""
  ) else (
    set "ARGS="--venv" "%VENV_OVERRIDE%""
  )
)
set "CMD=%UV_BIN% run --python 3.12 --no-project python quickserver.py !ARGS!"
call %CMD%
exit /b %ERRORLEVEL%
