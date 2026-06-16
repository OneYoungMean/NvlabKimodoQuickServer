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
set "VENV_PY=%~9"

set "LOG_DIR=%ROOT_DIR%\log"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not defined DOWNLOAD_LOG_PATH set "DOWNLOAD_LOG_PATH=%LOG_DIR%\download_model.log"

if "%USING_EXTERNAL_MODELS%"=="1" (
  echo [STEP] External models mode enabled, skip download_model.
  exit /b 0
)

call :decide_download_gguf
set "KIMODO_DOWNLOAD_GGUF=!DOWNLOAD_GGUF!"

echo [STEP] Downloading model assets for model=%MODEL_NAME% highvram=%HIGHVRAM% gguf=!DOWNLOAD_GGUF!...
set "GGUF_ARG="
if /I "!DOWNLOAD_GGUF!"=="1" set "GGUF_ARG=--download-gguf"
if "%HIGHVRAM%"=="1" (
  if /I "!DOWNLOAD_GGUF!"=="1" (
    echo [INFO] GGUF mode takes priority over highvram; skipping full text-encoder assets.
    call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%DOWNLOAD_LOG_PATH%" --unlock-stale --model "%MODEL_RUN_NAME%" !GGUF_ARG!
  ) else (
    call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%DOWNLOAD_LOG_PATH%" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram !GGUF_ARG!
  )
) else (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%DOWNLOAD_LOG_PATH%" --unlock-stale --model "%MODEL_RUN_NAME%" !GGUF_ARG!
)
if errorlevel 1 exit /b 1

exit /b 0

:decide_download_gguf
:: Decide whether the GGUF text encoder must be downloaded.
:: Rule (by total VRAM): <2GB or <6GB -> GGUF; >=6GB -> local encoder.
:: User override KIMODO_DOWNLOAD_GGUF wins.
set "DOWNLOAD_GGUF=0"
if defined KIMODO_DOWNLOAD_GGUF (
  set "DOWNLOAD_GGUF=%KIMODO_DOWNLOAD_GGUF%"
  echo [INFO] KIMODO_DOWNLOAD_GGUF override -^> !DOWNLOAD_GGUF!
  exit /b 0
)
set "VRAM_TOTAL_GB=none"
if defined VENV_PY if exist "!VENV_PY!" (
  for /f "usebackq delims=" %%V in (`"!VENV_PY!" -c "import torch; print(round(torch.cuda.get_device_properties(0).total_memory/1073741824,2) if (torch.cuda.is_available() and torch.cuda.device_count()>0) else 'none')" 2^>nul`) do set "VRAM_TOTAL_GB=%%V"
)
if /I "!VRAM_TOTAL_GB!"=="none" (
  echo [INFO] No usable GPU detected -^> GGUF download enabled.
  set "DOWNLOAD_GGUF=1"
  exit /b 0
)
set "VRAM_DECISION=local"
for /f "usebackq delims=" %%R in (`"!VENV_PY!" -c "print('gguf' if float('!VRAM_TOTAL_GB!')<6.0 else 'local')" 2^>nul`) do set "VRAM_DECISION=%%R"
if /I "!VRAM_DECISION!"=="gguf" (
  echo [INFO] VRAM=!VRAM_TOTAL_GB!GB ^(^<6GB^) -^> GGUF download enabled.
  set "DOWNLOAD_GGUF=1"
) else (
  echo [INFO] VRAM=!VRAM_TOTAL_GB!GB ^(^>=6GB^) -^> local encoder.
  set "DOWNLOAD_GGUF=0"
)
exit /b 0
