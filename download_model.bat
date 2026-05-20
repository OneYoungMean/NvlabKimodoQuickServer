@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "MODELS_DIR=%ROOT_DIR%\models"
set "OUTPUT_MODE=console"
set "LOG_PATH=%ROOT_DIR%\download_model.log"
set "UNLOCK_STALE=0"
set "TARGET=all"

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
if /I "%~1"=="--unlock-stale" (
  set "UNLOCK_STALE=1"
  shift
  goto parse_args
)
if /I "%~1"=="--target" (
  set "TARGET=%~2"
  shift
  shift
  goto parse_args
)
shift
goto parse_args

:parsed
if /I "%OUTPUT_MODE%"=="file" (
  call :main > "%LOG_PATH%" 2>&1
  set "RC=%ERRORLEVEL%"
  echo [INFO] download_model log: %LOG_PATH%
  exit /b %RC%
)
call :main
exit /b %ERRORLEVEL%

:main
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%" >nul 2>nul

call :ensure_git || exit /b 1
call :ensure_git_lfs || exit /b 1

echo [STEP] Downloading models (single-thread)...
if /I "%TARGET%"=="all" (
  call :ensure_repo "https://www.modelscope.cn/nv-community/Kimodo-SOMA-RP-v1.1.git" "%MODELS_DIR%\Kimodo-SOMA-RP-v1" "model.safetensors" || exit /b 1
  call :ensure_repo "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" "%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4" "model.safetensors" || exit /b 1
) else if /I "%TARGET%"=="soma" (
  call :ensure_repo "https://www.modelscope.cn/nv-community/Kimodo-SOMA-RP-v1.1.git" "%MODELS_DIR%\Kimodo-SOMA-RP-v1" "model.safetensors" || exit /b 1
) else if /I "%TARGET%"=="nf4" (
  call :ensure_repo "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" "%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4" "model.safetensors" || exit /b 1
) else (
  echo [ERROR] Unknown --target: %TARGET%
  exit /b 1
)

echo [OK] download_model complete.
exit /b 0

:ensure_git
set "GIT_HINT=%ROOT_DIR%\tools\PortableGit\cmd"
git --version >nul 2>nul
if not errorlevel 1 exit /b 0
if exist "%GIT_HINT%\git.exe" (
  set "PATH=%GIT_HINT%;%PATH%"
  git --version >nul 2>nul
  if not errorlevel 1 exit /b 0
)
echo [ERROR] git not found.
echo [ERROR] Install git or place portable git at: %GIT_HINT%
exit /b 1

:ensure_git_lfs
git lfs version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git-lfs not found. Please install git-lfs.
  exit /b 1
)
git lfs install --skip-repo >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git lfs install failed.
  exit /b 1
)
exit /b 0

:ensure_repo
set "REPO_URL=%~1"
set "DEST_DIR=%~2"
set "REQ_FILE=%~3"

if exist "%DEST_DIR%\%REQ_FILE%" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)

if exist "%DEST_DIR%" (
  if not exist "%DEST_DIR%\.git" (
    call :backup_dir "%DEST_DIR%" || exit /b 1
  )
)

if not exist "%DEST_DIR%" (
  echo [STEP] Cloning %REPO_URL%
  git clone "%REPO_URL%" "%DEST_DIR%"
  if errorlevel 1 exit /b 1
) else (
  call :prepare_repo "%DEST_DIR%" || exit /b 1
  echo [STEP] Updating existing repo: %DEST_DIR%
  git -C "%DEST_DIR%" pull
  if errorlevel 1 (
    call :backup_dir "%DEST_DIR%" || exit /b 1
    echo [STEP] Re-cloning %REPO_URL%
    git clone "%REPO_URL%" "%DEST_DIR%"
    if errorlevel 1 exit /b 1
  )
)

call :prepare_repo "%DEST_DIR%" || exit /b 1
git -C "%DEST_DIR%" lfs pull --include="%REQ_FILE%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\%REQ_FILE%" (
  git -C "%DEST_DIR%" checkout HEAD -- "%REQ_FILE%"
  if errorlevel 1 exit /b 1
  git -C "%DEST_DIR%" lfs pull --include="%REQ_FILE%"
  if errorlevel 1 exit /b 1
)
if not exist "%DEST_DIR%\%REQ_FILE%" (
  echo [ERROR] Missing %REQ_FILE% after sync: %DEST_DIR%
  exit /b 1
)
exit /b 0

:prepare_repo
set "REPO_DIR=%~1"
if "%UNLOCK_STALE%"=="1" call :rotate_lock "%REPO_DIR%"
git -C "%REPO_DIR%" rev-parse --verify HEAD >nul 2>nul
if not errorlevel 1 exit /b 0
call :backup_dir "%REPO_DIR%" || exit /b 1
exit /b 0

:rotate_lock
set "LOCK_FILE=%~1\.git\index.lock"
if exist "%LOCK_FILE%" (
  set "LOCK_BAK=%LOCK_FILE%.stale.%RANDOM%%RANDOM%"
  move "%LOCK_FILE%" "%LOCK_BAK%" >nul
  if errorlevel 1 (
    echo [ERROR] Failed to rotate stale lock: %LOCK_FILE%
    exit /b 1
  )
  echo [WARN] Rotated stale lock: %LOCK_BAK%
)
exit /b 0

:backup_dir
set "DIR_TO_BACKUP=%~1"
if not exist "%DIR_TO_BACKUP%" exit /b 0
set "BACKUP_DIR=%DIR_TO_BACKUP%.broken.%RANDOM%%RANDOM%"
move "%DIR_TO_BACKUP%" "%BACKUP_DIR%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to backup: %DIR_TO_BACKUP%
  exit /b 1
)
echo [WARN] Backed up to: %BACKUP_DIR%
exit /b 0
