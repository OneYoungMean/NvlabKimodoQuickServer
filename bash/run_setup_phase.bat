@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~1"
set "OUTPUT_MODE=%~2"
set "USING_EXTERNAL_VENV=%~3"
set "SETUP_SENTINEL=%~4"
set "SETUP_BAT=%~5"
set "SETUP_LOG_PATH=%~6"
set "SETUP_DEVICE=%~7"

set "LOG_DIR=%ROOT_DIR%\log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not defined SETUP_LOG_PATH set "SETUP_LOG_PATH=%LOG_DIR%\setup.log"
if /I not "%SETUP_DEVICE%"=="cpu" set "SETUP_DEVICE=auto"

if "%USING_EXTERNAL_VENV%"=="1" (
  echo [STEP] External venv mode enabled, skip setup.
  exit /b 0
)

echo [STEP] Validating setup completeness for mode=%SETUP_DEVICE%...
set "PREV_SETUP_DEVICE=%KIMODO_SETUP_DEVICE%"
set "KIMODO_SETUP_DEVICE=%SETUP_DEVICE%"
call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%SETUP_LOG_PATH%"
set "SETUP_RC=%ERRORLEVEL%"
if defined PREV_SETUP_DEVICE (
  set "KIMODO_SETUP_DEVICE=%PREV_SETUP_DEVICE%"
) else (
  set "KIMODO_SETUP_DEVICE="
)
if not "%SETUP_RC%"=="0" exit /b %SETUP_RC%

exit /b 0
