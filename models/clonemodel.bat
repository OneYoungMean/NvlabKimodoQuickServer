@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "MODELS_DIR=%SCRIPT_DIR%"
set "GIT_INSTALLER_PS1=%SCRIPT_DIR%\install_git_and_lfs.ps1"
set "GIT_ENV_TMP=%TEMP%\kimodo_git_env_%RANDOM%%RANDOM%.cmd"
set "HIGHVRAM=0"
set "WANT_SMPLX=0"
set "WANT_G1=0"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="-highvram" (
  set "HIGHVRAM=1"
  shift
  goto parse_args
)
if /I "%~1"=="--highvram" (
  set "HIGHVRAM=1"
  shift
  goto parse_args
)
if /I "%~1"=="-smplx" (
  set "WANT_SMPLX=1"
  shift
  goto parse_args
)
if /I "%~1"=="--smplx" (
  set "WANT_SMPLX=1"
  shift
  goto parse_args
)
if /I "%~1"=="-g1" (
  set "WANT_G1=1"
  shift
  goto parse_args
)
if /I "%~1"=="--g1" (
  set "WANT_G1=1"
  shift
  goto parse_args
)
shift
goto parse_args

:args_done
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%" >nul 2>nul
if exist "%GIT_INSTALLER_PS1%" (
  echo [STEP] Ensuring git + git-lfs...
  if exist "%GIT_ENV_TMP%" del /q "%GIT_ENV_TMP%" >nul 2>nul
  powershell -NoProfile -File "%GIT_INSTALLER_PS1%" -Quiet -EmitEnvFile "%GIT_ENV_TMP%"
  if errorlevel 1 (
    >&2 echo [ERROR] Failed to auto-install git/git-lfs.
    exit /b 1
  )
  if exist "%GIT_ENV_TMP%" (
    call "%GIT_ENV_TMP%"
    del /q "%GIT_ENV_TMP%" >nul 2>nul
  )
)
call :ensure_git_lfs || exit /b 1

rem Default: always prepare SOMA checkpoint and NF4 text-encoder.
call :ensure_soma_checkpoint || exit /b 1
call :ensure_kimodo_nf4 || exit /b 1

if "%HIGHVRAM%"=="1" (
  call :ensure_meta_llama || exit /b 1
  call :ensure_llm2vec_supervised || exit /b 1
)
if "%WANT_SMPLX%"=="1" call :ensure_smplx_checkpoint || exit /b 1
if "%WANT_G1%"=="1" call :ensure_g1_checkpoint || exit /b 1

echo [OK] Model clone complete.
exit /b 0

:ensure_git_lfs
git --version >nul 2>nul
if errorlevel 1 (
  >&2 echo [ERROR] git is not installed or not on PATH.
  exit /b 1
)
git lfs version >nul 2>nul
if errorlevel 1 (
  >&2 echo [ERROR] git lfs is not installed or not on PATH.
  exit /b 1
)
git lfs install --skip-repo >nul 2>nul
exit /b 0

:clone_repo
set "REPO_URL=%~1"
set "DEST_DIR=%~2"
for %%D in ("%DEST_DIR%") do set "PARENT_DIR=%%~dpD"
if not exist "%PARENT_DIR%" mkdir "%PARENT_DIR%" >nul 2>nul

if exist "%DEST_DIR%" (
  if not exist "%DEST_DIR%\.git" (
    echo [WARN] Existing directory is not a git repo, backing up then re-cloning: %DEST_DIR%
    call :backup_dir "%DEST_DIR%" || exit /b 1
  ) else (
    git -C "%DEST_DIR%" rev-parse --verify HEAD >nul 2>nul
    if errorlevel 1 (
      echo [WARN] Repo has invalid HEAD, backing up then re-cloning: %DEST_DIR%
      call :backup_dir "%DEST_DIR%" || exit /b 1
    )
  )
)

if not exist "%DEST_DIR%" (
  echo [STEP] Cloning %REPO_URL%
  git clone "%REPO_URL%" "%DEST_DIR%"
  if errorlevel 1 exit /b 1
) else (
  echo [STEP] Updating existing repo: %DEST_DIR%
  git -C "%DEST_DIR%" pull
  if errorlevel 1 (
    echo [WARN] git pull failed, backing up and re-cloning: %DEST_DIR%
    call :backup_dir "%DEST_DIR%" || exit /b 1
    echo [STEP] Re-cloning %REPO_URL%
    git clone "%REPO_URL%" "%DEST_DIR%"
    if errorlevel 1 exit /b 1
  )
)
git -C "%DEST_DIR%" lfs pull
if errorlevel 1 exit /b 1
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
echo [INFO] Backed up to: %BACKUP_DIR%
exit /b 0

:ensure_soma_checkpoint
set "DEST_DIR=%MODELS_DIR%\Kimodo-SOMA-RP-v1"
if exist "%DEST_DIR%\model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/nv-community/Kimodo-SOMA-RP-v1.1.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\model.safetensors" (
  >&2 echo [ERROR] Missing model.safetensors after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0

:ensure_smplx_checkpoint
set "DEST_DIR=%MODELS_DIR%\Kimodo-SMPLX-RP-v1"
if exist "%DEST_DIR%\model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/nv-community/Kimodo-SMPLX-RP-v1.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\model.safetensors" (
  >&2 echo [ERROR] Missing model.safetensors after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0

:ensure_g1_checkpoint
set "DEST_DIR=%MODELS_DIR%\Kimodo-G1-RP-v1"
if exist "%DEST_DIR%\model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/nv-community/Kimodo-G1-RP-v1.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\model.safetensors" (
  >&2 echo [ERROR] Missing model.safetensors after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0

:ensure_kimodo_nf4
set "DEST_DIR=%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4"
if exist "%DEST_DIR%\model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\model.safetensors" (
  >&2 echo [ERROR] Missing model.safetensors after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0

:ensure_meta_llama
set "DEST_DIR=%MODELS_DIR%\Meta-Llama-3-8B-Instruct"
if exist "%DEST_DIR%\model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
if exist "%DEST_DIR%\model.safetensors.index.json" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/LLM-Research/Meta-Llama-3-8B-Instruct.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\config.json" (
  >&2 echo [ERROR] Missing config.json after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0

:ensure_llm2vec_supervised
set "DEST_DIR=%MODELS_DIR%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
if exist "%DEST_DIR%\adapter_model.safetensors" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
if exist "%DEST_DIR%\adapter_model.bin" (
  echo [INFO] Skip existing model: %DEST_DIR%
  exit /b 0
)
call :clone_repo "https://www.modelscope.cn/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised.git" "%DEST_DIR%"
if errorlevel 1 exit /b 1
if not exist "%DEST_DIR%\adapter_config.json" (
  >&2 echo [ERROR] Missing adapter_config.json after clone: %DEST_DIR%
  exit /b 1
)
exit /b 0
