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

if "%USING_EXTERNAL_VENV%"=="1" (
  echo [STEP] External venv mode enabled, skip setup.
  exit /b 0
)

if not exist "%SETUP_SENTINEL%" (
  echo [STEP] setup not found, running setup...
  if not defined SETUP_DEVICE set "SETUP_DEVICE=%KIMODO_SETUP_DEVICE%"
  if /I not "%SETUP_DEVICE%"=="cpu" if /I not "%SETUP_DEVICE%"=="cuda" set "SETUP_DEVICE="
  if defined SETUP_DEVICE (
    call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%SETUP_LOG_PATH%" --device %SETUP_DEVICE%
  ) else (
    call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%SETUP_LOG_PATH%"
  )
  if errorlevel 1 exit /b 1
)

exit /b 0
