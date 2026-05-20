@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "OUTPUT_MODE=console"
set "LOG_PATH=%ROOT_DIR%\run_server.log"
set "SETUP_BAT=%ROOT_DIR%\setup.bat"
set "SETUP_LOCK=%ROOT_DIR%\.setup_new.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup_new_complete"
set "SOURCE_ROOT="

:parse_args
if "%~1"=="" goto parsed
if /I "%~1"=="--model" (
  set "MODEL_NAME=%~2"
  shift
  shift
  goto parse_args
)
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
if /I "%~1"=="--force-setup" (
  if exist "%SETUP_SENTINEL%" del /q "%SETUP_SENTINEL%" >nul 2>nul
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

if exist "%SETUP_LOCK%" (
  echo [ERROR] setup is running: %SETUP_LOCK%
  exit /b 1
)

if not exist "%SETUP_SENTINEL%" (
  echo [STEP] setup not found, running setup...
  call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%ROOT_DIR%\setup.log"
  if errorlevel 1 exit /b 1
)

set "VENV_PY=%ROOT_DIR%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)
if not exist "%ROOT_DIR%\models\Kimodo-SOMA-RP-v1\model.safetensors" (
  echo [ERROR] Missing SOMA model file.
  exit /b 1
)
if not exist "%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4\model.safetensors" (
  echo [ERROR] Missing NF4 model file.
  exit /b 1
)

set "PYTHONPATH=%SOURCE_ROOT%"
set "KIMODO_ROOT_PATH=%ROOT_DIR%"
set "CHECKPOINT_DIR=%ROOT_DIR%\models"
set "LOCAL_CACHE=true"
set "TEXT_ENCODER_MODE=local"
set "TEXT_ENCODER=llm2vec"
set "HF_HOME=%ROOT_DIR%\hf_cache"
set "TRANSFORMERS_CACHE=%HF_HOME%\transformers"
set "HUGGINGFACE_HUB_CACHE=%HF_HOME%\hub"
set "HF_HUB_CACHE=%HF_HOME%\hub"
set "TRANSFORMERS_OFFLINE=1"
set "HF_HUB_OFFLINE=1"
set "HF_DATASETS_OFFLINE=1"
set "PYTHONUNBUFFERED=1"

if not exist "%HF_HOME%" mkdir "%HF_HOME%" >nul 2>nul
if not exist "%TRANSFORMERS_CACHE%" mkdir "%TRANSFORMERS_CACHE%" >nul 2>nul
if not exist "%HUGGINGFACE_HUB_CACHE%" mkdir "%HUGGINGFACE_HUB_CACHE%" >nul 2>nul

if /I "%OUTPUT_MODE%"=="file" (
  set "LOG_USED=%LOG_PATH%"
  if exist "!LOG_USED!" set "LOG_USED=%ROOT_DIR%\\run_server_!RANDOM!!RANDOM!.log"
  echo [INFO] run_server log: !LOG_USED!
  pushd "%ROOT_DIR%" >nul
  "%VENV_PY%" -u -m kimodo.bridge.bridge_server --model "%MODEL_NAME%" --kimodo-root "%ROOT_DIR%" > "!LOG_USED!" 2>&1
  set "RC=%ERRORLEVEL%"
  popd >nul
  exit /b %RC%
)

pushd "%ROOT_DIR%" >nul
"%VENV_PY%" -u -m kimodo.bridge.bridge_server --model "%MODEL_NAME%" --kimodo-root "%ROOT_DIR%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%
