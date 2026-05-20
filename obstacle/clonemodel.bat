@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODELS_DIR=%SCRIPT_DIR%"
set "GIT_INSTALLER_PS1=%SCRIPT_DIR%\install_git_and_lfs.ps1"
set "GIT_ENV_TMP=%TEMP%\kimodo_git_env_%RANDOM%%RANDOM%.cmd"

if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%" >nul 2>nul

if exist "%GIT_INSTALLER_PS1%" (
  echo [STEP] Ensuring git + git-lfs...
  powershell -NoProfile -ExecutionPolicy Bypass -File "%GIT_INSTALLER_PS1%" -Quiet -EmitEnvFile "%GIT_ENV_TMP%"
  if errorlevel 1 (
    >&2 echo [ERROR] Failed to prepare git/git-lfs.
    exit /b 1
  )
  if exist "%GIT_ENV_TMP%" call "%GIT_ENV_TMP%"
)

call :ensure_git_lfs || exit /b 1
call :ensure_repo "https://www.modelscope.cn/nv-community/Kimodo-SOMA-RP-v1.1.git" "%MODELS_DIR%\Kimodo-SOMA-RP-v1" "model.safetensors" || exit /b 1
call :ensure_repo "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" "%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4" "model.safetensors" || exit /b 1

echo [OK] Model clone complete.
exit /b 0

:ensure_git_lfs
git --version >nul 2>nul
if errorlevel 1 (
  >&2 echo [ERROR] git is not available.
  exit /b 1
)
git lfs version >nul 2>nul
if errorlevel 1 (
  >&2 echo [ERROR] git-lfs is not available.
  exit /b 1
)
git lfs install --skip-repo >nul 2>nul
if errorlevel 1 (
  >&2 echo [ERROR] git lfs install failed.
  exit /b 1
)
exit /b 0

:backup_dir
set "DIR_TO_BACKUP=%~1"
if not exist "%DIR_TO_BACKUP%" exit /b 0
set "BACKUP_DIR=%DIR_TO_BACKUP%.broken.%RANDOM%%RANDOM%"
move "%DIR_TO_BACKUP%" "%BACKUP_DIR%" >nul
if errorlevel 1 (
  >&2 echo [ERROR] Failed to backup directory: %DIR_TO_BACKUP%
  exit /b 1
)
echo [WARN] Backed up: %BACKUP_DIR%
exit /b 0

:clear_repo_lock
set "LOCK_FILE=%~1\.git\index.lock"
if exist "%LOCK_FILE%" (
  set "LOCK_BAK=%LOCK_FILE%.stale.%RANDOM%%RANDOM%"
  move "%LOCK_FILE%" "%LOCK_BAK%" >nul
  if errorlevel 1 (
    >&2 echo [ERROR] Failed to rotate stale lock: %LOCK_FILE%
    exit /b 1
  )
  echo [WARN] Rotated stale git lock: %LOCK_BAK%
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
  call :clear_repo_lock "%DEST_DIR%" || exit /b 1
  echo [STEP] Updating existing repo: %DEST_DIR%
  git -C "%DEST_DIR%" pull
  if errorlevel 1 (
    call :backup_dir "%DEST_DIR%" || exit /b 1
    echo [STEP] Re-cloning %REPO_URL%
    git clone "%REPO_URL%" "%DEST_DIR%"
    if errorlevel 1 exit /b 1
  )
)

call :clear_repo_lock "%DEST_DIR%" || exit /b 1
git -C "%DEST_DIR%" lfs pull --include="%REQ_FILE%"
if errorlevel 1 exit /b 1

if not exist "%DEST_DIR%\%REQ_FILE%" (
  git -C "%DEST_DIR%" checkout HEAD -- "%REQ_FILE%"
  if errorlevel 1 exit /b 1
  git -C "%DEST_DIR%" lfs pull --include="%REQ_FILE%"
  if errorlevel 1 exit /b 1
)

if not exist "%DEST_DIR%\%REQ_FILE%" (
  >&2 echo [ERROR] Missing %REQ_FILE% after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0
