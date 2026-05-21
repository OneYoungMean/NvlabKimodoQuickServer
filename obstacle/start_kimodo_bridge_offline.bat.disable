@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--model" (
  set "MODEL_NAME=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--kimodo-root" (
  set "ROOT_DIR=%~2"
  shift
  shift
  goto parse_args
)
shift
goto parse_args

:args_done
set "SETUP_BAT=%ROOT_DIR%\setup_kimodo_offline.bat"
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.kimodo_offline_setup_complete"
set "VENV_PY=%ROOT_DIR%\.venv\Scripts\python.exe"
set "SOURCE_ROOT="
if exist "%ROOT_DIR%\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%"
if not defined SOURCE_ROOT if exist "%ROOT_DIR%\kimodo\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%\kimodo"
if not defined SOURCE_ROOT (
  >&2 echo [ERROR] Invalid project root: %ROOT_DIR%
  exit /b 1
)

if exist "%SETUP_LOCK%" (
  >&2 echo [ERROR] Setup is running: %SETUP_LOCK%
  exit /b 1
)

if not exist "%SETUP_SENTINEL%" (
  echo [STEP] First-time setup required, running setup...
  call "%SETUP_BAT%"
  if errorlevel 1 exit /b 1
)

if not exist "%VENV_PY%" (
  >&2 echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)
if not exist "%ROOT_DIR%\models\Kimodo-SOMA-RP-v1\model.safetensors" (
  >&2 echo [ERROR] Missing checkpoint model.
  exit /b 1
)
if not exist "%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4\model.safetensors" (
  >&2 echo [ERROR] Missing NF4 text encoder model.
  exit /b 1
)

set "PYTHONPATH=%SOURCE_ROOT%"
set "KIMODO_ROOT_PATH=%ROOT_DIR%"
set "HF_HOME=%ROOT_DIR%\hf_cache"
set "TRANSFORMERS_CACHE=%HF_HOME%\transformers"
set "HUGGINGFACE_HUB_CACHE=%HF_HOME%\hub"
set "HF_HUB_CACHE=%HF_HOME%\hub"
set "TRANSFORMERS_OFFLINE=1"
set "HF_HUB_OFFLINE=1"
set "HF_DATASETS_OFFLINE=1"
set "PYTHONUNBUFFERED=1"

if not exist "%HF_HOME%" mkdir "%HF_HOME%"
if not exist "%TRANSFORMERS_CACHE%" mkdir "%TRANSFORMERS_CACHE%"
if not exist "%HUGGINGFACE_HUB_CACHE%" mkdir "%HUGGINGFACE_HUB_CACHE%"

pushd "%ROOT_DIR%" >nul
"%VENV_PY%" -u -m kimodo.bridge.bridge_server --model "%MODEL_NAME%" --kimodo-root "%ROOT_DIR%"
set "EXIT_CODE=%ERRORLEVEL%"
popd >nul
exit /b %EXIT_CODE%
