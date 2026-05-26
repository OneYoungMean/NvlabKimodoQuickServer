@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~1"
set "OUTPUT_MODE=%~2"
set "USING_EXTERNAL_MODELS=%~3"
set "HIGHVRAM=%~4"
set "MODEL_RUN_NAME=%~5"
set "MODEL_NAME=%~6"
set "DOWNLOAD_BAT=%~7"
set "DOWNLOAD_LOG_PATH=%~8"

set "LOG_DIR=%ROOT_DIR%\log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not defined DOWNLOAD_LOG_PATH set "DOWNLOAD_LOG_PATH=%LOG_DIR%\download_model.log"

if "%USING_EXTERNAL_MODELS%"=="1" (
  echo [STEP] External models mode enabled, skip download_model.
  exit /b 0
)

echo [STEP] Downloading model assets for model=%MODEL_NAME% highvram=%HIGHVRAM%...
set "GGUF_ARG="
if /I "%KIMODO_DOWNLOAD_GGUF%"=="1" set "GGUF_ARG=--download-gguf"
if "%HIGHVRAM%"=="1" (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%DOWNLOAD_LOG_PATH%" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram %GGUF_ARG%
) else (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%DOWNLOAD_LOG_PATH%" --unlock-stale --model "%MODEL_RUN_NAME%" %GGUF_ARG%
)
if errorlevel 1 exit /b 1

exit /b 0
