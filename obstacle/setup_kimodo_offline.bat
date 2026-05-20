@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%~dp0"
if "%ROOT_DIR:~-1%"=="\" set "ROOT_DIR=%ROOT_DIR:~0,-1%"
set "SOURCE_ROOT="
set "LOCK_FILE=%ROOT_DIR%\.setup.lock"
set "RUN_MARKER=%ROOT_DIR%\run"
set "SETUP_SENTINEL=%ROOT_DIR%\.kimodo_offline_setup_complete"
set "SETUP_LOG=%ROOT_DIR%\setup_kimodo_offline.log"
set "BUILD_IMPL=%ROOT_DIR%\setup_kimodo_offline_impl.bat"
set "CLONE_BAT=%ROOT_DIR%\models\clonemodel.bat"

if exist "%ROOT_DIR%\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%"
if not defined SOURCE_ROOT if exist "%ROOT_DIR%\kimodo\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%\kimodo"
if not defined SOURCE_ROOT (
  echo [ERROR] Invalid project root: %ROOT_DIR%
  exit /b 1
)

if not exist "%BUILD_IMPL%" (
  echo [ERROR] Missing build script: %BUILD_IMPL%
  exit /b 1
)
if not exist "%CLONE_BAT%" (
  echo [ERROR] Missing model script: %CLONE_BAT%
  exit /b 1
)

> "%LOCK_FILE%" (
  echo started=%DATE% %TIME%
  echo root=%ROOT_DIR%
)

echo [INFO] Setup log: %SETUP_LOG%
call :run_setup > "%SETUP_LOG%" 2>&1
set "SETUP_EXIT=%ERRORLEVEL%"

if "%SETUP_EXIT%"=="0" (
  if not exist "%RUN_MARKER%" mkdir "%RUN_MARKER%"
  > "%SETUP_SENTINEL%" (
    echo setup_time=%DATE% %TIME%
    echo root_dir=%ROOT_DIR%
    echo source_root=%SOURCE_ROOT%
  )
  echo [OK] Offline setup staged.
) else (
  echo [ERROR] Setup failed. See %SETUP_LOG%
)

if exist "%LOCK_FILE%" del /q "%LOCK_FILE%" >nul 2>nul
exit /b %SETUP_EXIT%

:run_setup
echo [STEP] Build environment...
set "KIMODO_BUILDENV_ONLY=1"
set "KIMODO_SETUP_BG=1"
call "%BUILD_IMPL%"
if errorlevel 1 exit /b 1
set "KIMODO_BUILDENV_ONLY="
set "KIMODO_SETUP_BG="

echo [STEP] Clone required models...
pushd "%ROOT_DIR%\models" >nul
call "%CLONE_BAT%"
set "CLONE_EXIT=%ERRORLEVEL%"
popd >nul
if not "%CLONE_EXIT%"=="0" exit /b %CLONE_EXIT%

set "VENV_PY=%ROOT_DIR%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)
if not exist "%ROOT_DIR%\models\Kimodo-SOMA-RP-v1\model.safetensors" (
  echo [ERROR] Missing checkpoint: %ROOT_DIR%\models\Kimodo-SOMA-RP-v1\model.safetensors
  exit /b 1
)
if not exist "%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4\model.safetensors" (
  echo [ERROR] Missing text encoder: %ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4\model.safetensors
  exit /b 1
)

set "PYTHONPATH=%SOURCE_ROOT%"
"%VENV_PY%" -c "import numpy, kimodo, huggingface_hub, safetensors"
if errorlevel 1 (
  echo [ERROR] Runtime import check failed.
  exit /b 1
)

echo [OK] Setup completed.
exit /b 0
