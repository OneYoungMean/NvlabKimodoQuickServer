@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "SCRIPT_DIR=%%~fI"
if "!SCRIPT_DIR:~-1!"=="\" set "SCRIPT_DIR=!SCRIPT_DIR:~0,-1!"
for %%I in ("!SCRIPT_DIR!\..") do set "ROOT_DIR=%%~fI"
set "LOG_DIR=!ROOT_DIR!\log"
set "SOURCE_ROOT="
set "OUTPUT_MODE=console"
set "LOG_PATH=!LOG_DIR!\setup.log"
set "LOCK_FILE=!ROOT_DIR!\.setup.lock"
set "SENTINEL=!ROOT_DIR!\.setup.complete"
set "SETUP_BUILD_IMPL=!ROOT_DIR!\bash\setup_buildenv_impl.bat"
set "RECYCLE_DIR=!ROOT_DIR!\archive\recycle"
set "REQUESTED_SETUP_MODE=%KIMODO_SETUP_DEVICE%"
if not defined REQUESTED_SETUP_MODE set "REQUESTED_SETUP_MODE=%KIMODO_TEST_SETUP_DEVICE%"
if /I "!REQUESTED_SETUP_MODE!"=="cpu" (
  set "REQUESTED_SETUP_MODE=cpu"
) else (
  set "REQUESTED_SETUP_MODE=auto"
)

:parse_args
if "%~1"=="" goto parsed
if /I "%~1"=="--output" (
  set "OUTPUT_MODE=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--log" (
  set "LOG_PATH=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--force" (
  call :archive_file "%SENTINEL%"
  shift
  goto parse_args
)
shift
goto parse_args

:parsed
if exist "!ROOT_DIR!\pyproject.toml" set "SOURCE_ROOT=!ROOT_DIR!"
if not defined SOURCE_ROOT if exist "!ROOT_DIR!\kimodo\pyproject.toml" set "SOURCE_ROOT=!ROOT_DIR!\kimodo"
if not defined SOURCE_ROOT (
  echo [ERROR] Invalid project root: !ROOT_DIR!
  exit /b 1
)
if not exist "!LOG_DIR!" mkdir "!LOG_DIR!" >nul 2>nul
set "KIMODO_SETUP_DEVICE=!REQUESTED_SETUP_MODE!"

if exist "!LOCK_FILE!" (
  echo [ERROR] setup already running: !LOCK_FILE!
  exit /b 1
)

if exist "!SENTINEL!" (
  set "SENTINEL_DEVICE="
  set "SENTINEL_TORCH_RUNTIME="
  for /f "usebackq tokens=1,* delims==" %%A in ("!SENTINEL!") do (
    if /I "%%A"=="setup_mode" set "SENTINEL_DEVICE=%%B"
    if /I "%%A"=="torch_runtime" set "SENTINEL_TORCH_RUNTIME=%%B"
  )
  if /I "!SENTINEL_DEVICE!"=="!REQUESTED_SETUP_MODE!" (
    if defined SENTINEL_TORCH_RUNTIME (
      echo [INFO] setup already completed: !SENTINEL! ^(mode=!SENTINEL_DEVICE!, torch=!SENTINEL_TORCH_RUNTIME!^)
    ) else (
      echo [INFO] setup already completed: !SENTINEL! ^(mode=!SENTINEL_DEVICE!^)
    )
    exit /b 0
  )
  if not defined SENTINEL_DEVICE set "SENTINEL_DEVICE=unknown"
  echo [INFO] setup sentinel mode mismatch ^(found=!SENTINEL_DEVICE!, want=!REQUESTED_SETUP_MODE!^), re-running setup.
  call :archive_file "!SENTINEL!"
)

> "!LOCK_FILE!" (
  echo started=%DATE% %TIME%
  echo root="!ROOT_DIR!"
)

if /I "%OUTPUT_MODE%"=="file" (
  call :main > "!LOG_PATH!" 2>&1
  set "RC=%ERRORLEVEL%"
  call :archive_file "!LOCK_FILE!"
  if "%RC%"=="0" echo [INFO] setup log: !LOG_PATH!
  exit /b %RC%
)

call :main
set "RC=%ERRORLEVEL%"
call :archive_file "!LOCK_FILE!"
exit /b %RC%

:main
echo [STEP] Build env (single-thread)...
echo [INFO] setup mode: !REQUESTED_SETUP_MODE!
if not exist "!SETUP_BUILD_IMPL!" (
  echo [ERROR] Missing build impl: !SETUP_BUILD_IMPL!
  exit /b 1
)
set "KIMODO_BUILDENV_ONLY=1"
set "KIMODO_SETUP_BG=1"
pushd "!ROOT_DIR!" >nul
call "!SETUP_BUILD_IMPL!"
set "BUILD_RC=%ERRORLEVEL%"
popd >nul
if not "%BUILD_RC%"=="0" exit /b %BUILD_RC%
set "KIMODO_BUILDENV_ONLY="
set "KIMODO_SETUP_BG="

set "VENV_PY=%SOURCE_ROOT%\.venv\Scripts\python.exe"
if not exist "!VENV_PY!" (
  echo [ERROR] Missing venv python: !VENV_PY!
  exit /b 1
)
set "PYTHONPATH=!SOURCE_ROOT!"
"!VENV_PY!" -c "import numpy, kimodo, huggingface_hub, safetensors, motion_correction"
if errorlevel 1 (
  echo [ERROR] Runtime import check failed.
  exit /b 1
)

set "TORCH_RUNTIME=unknown"
set "TORCH_RUNTIME_FILE=%TEMP%\kimodo_torch_runtime_%RANDOM%%RANDOM%.txt"
del /q "!TORCH_RUNTIME_FILE!" >nul 2>nul
"!VENV_PY!" -c "import torch; print('cuda' if torch.version.cuda is not None else 'cpu')" > "!TORCH_RUNTIME_FILE!" 2>nul
if exist "!TORCH_RUNTIME_FILE!" (
  set /p TORCH_RUNTIME=<"!TORCH_RUNTIME_FILE!"
  del /q "!TORCH_RUNTIME_FILE!" >nul 2>nul
)
if not defined TORCH_RUNTIME set "TORCH_RUNTIME=unknown"

> "!SENTINEL!" (
  echo setup_time=%DATE% %TIME%
  echo setup_mode=!REQUESTED_SETUP_MODE!
  echo torch_runtime=!TORCH_RUNTIME!
  echo root_dir="!ROOT_DIR!"
  echo source_root="!SOURCE_ROOT!"
)

echo [OK] setup complete.
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
if not exist "!ARCHIVE_TARGET!" exit /b 0
if not exist "!RECYCLE_DIR!" mkdir "!RECYCLE_DIR!" >nul 2>nul
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=!RECYCLE_DIR!\%BASE%.%TS%.%RANDOM%"
move "!ARCHIVE_TARGET!" "!DEST!" >nul 2>nul
exit /b 0


