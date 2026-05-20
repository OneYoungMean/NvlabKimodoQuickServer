@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"
set "SOURCE_ROOT="
set "OUTPUT_MODE=console"
set "LOG_PATH=%LOG_DIR%\setup.log"
set "LOCK_FILE=%ROOT_DIR%\.setup_new.lock"
set "SENTINEL=%ROOT_DIR%\.setup_new_complete"
set "SETUP_BUILD_IMPL=%ROOT_DIR%\bash\setup_buildenv_impl.bat"

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
  if exist "%SENTINEL%" del /q "%SENTINEL%" >nul 2>nul
  shift
  goto parse_args
)
shift
goto parse_args

:parsed
if exist "%ROOT_DIR%\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%"
if not defined SOURCE_ROOT if exist "%ROOT_DIR%\kimodo\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%\kimodo"
if not defined SOURCE_ROOT (
  echo [ERROR] Invalid project root: %ROOT_DIR%
  exit /b 1
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul

if exist "%LOCK_FILE%" (
  echo [ERROR] setup already running: %LOCK_FILE%
  exit /b 1
)

if exist "%SENTINEL%" (
  echo [INFO] setup already completed: %SENTINEL%
  exit /b 0
)

> "%LOCK_FILE%" (
  echo started=%DATE% %TIME%
  echo root=%ROOT_DIR%
)

if /I "%OUTPUT_MODE%"=="file" (
  call :main > "%LOG_PATH%" 2>&1
  set "RC=%ERRORLEVEL%"
  if exist "%LOCK_FILE%" del /q "%LOCK_FILE%" >nul 2>nul
  if "%RC%"=="0" echo [INFO] setup log: %LOG_PATH%
  exit /b %RC%
)

call :main
set "RC=%ERRORLEVEL%"
if exist "%LOCK_FILE%" del /q "%LOCK_FILE%" >nul 2>nul
exit /b %RC%

:main
echo [STEP] Build env (single-thread)...
if not exist "%SETUP_BUILD_IMPL%" (
  echo [ERROR] Missing build impl: %SETUP_BUILD_IMPL%
  exit /b 1
)
set "KIMODO_BUILDENV_ONLY=1"
set "KIMODO_SETUP_BG=1"
pushd "%ROOT_DIR%" >nul
call "%SETUP_BUILD_IMPL%"
set "BUILD_RC=%ERRORLEVEL%"
popd >nul
if not "%BUILD_RC%"=="0" exit /b %BUILD_RC%
set "KIMODO_BUILDENV_ONLY="
set "KIMODO_SETUP_BG="

set "VENV_PY=%SOURCE_ROOT%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)
set "PYTHONPATH=%SOURCE_ROOT%"
"%VENV_PY%" -c "import numpy, kimodo, huggingface_hub, safetensors"
if errorlevel 1 (
  echo [ERROR] Runtime import check failed.
  exit /b 1
)

> "%SENTINEL%" (
  echo setup_time=%DATE% %TIME%
  echo root_dir=%ROOT_DIR%
  echo source_root=%SOURCE_ROOT%
)

echo [OK] setup complete.
exit /b 0
