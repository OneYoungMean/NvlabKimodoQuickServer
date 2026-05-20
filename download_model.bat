@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "MODELS_DIR=%ROOT_DIR%\models"
set "OUTPUT_MODE=console"
set "LOG_PATH=%ROOT_DIR%\download_model.log"
set "UNLOCK_STALE=0"
set "FORCE_SYNC=0"
set "TARGET=all"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "USE_MODEL_ARG=0"
set "HIGHVRAM=0"
set "MODEL_DIR_NAME="
set "MODEL_REPO_URL="
set "LLM2VEC_NF4_REPO_URL=https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git"
set "META_LLAMA_REPO_URL=https://www.modelscope.cn/models/LLM-Research/Meta-Llama-3-8B-Instruct"
set "LLM2VEC_PEFT_REPO_URL=https://www.modelscope.cn/models/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
set "GIT_INSTALLER_PS1=%ROOT_DIR%\ensure_portable_git_lfs.ps1"
set "GIT_ENV_TMP=%TEMP%\kimodo_git_env_%RANDOM%%RANDOM%.cmd"

if defined KIMODO_LLM2VEC_NF4_REPO_URL set "LLM2VEC_NF4_REPO_URL=%KIMODO_LLM2VEC_NF4_REPO_URL%"
if defined KIMODO_META_LLAMA_REPO_URL set "META_LLAMA_REPO_URL=%KIMODO_META_LLAMA_REPO_URL%"
if defined KIMODO_LLM2VEC_PEFT_REPO_URL set "LLM2VEC_PEFT_REPO_URL=%KIMODO_LLM2VEC_PEFT_REPO_URL%"

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
if /I "%~1"=="--force" (
  set "FORCE_SYNC=1"
  shift
  goto parse_args
)
if /I "%~1"=="--target" (
  set "TARGET=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--model" (
  set "MODEL_NAME=%~2"
  set "USE_MODEL_ARG=1"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--highvram" (
  set "HIGHVRAM=1"
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

call :ensure_git_and_lfs || exit /b 1

echo [STEP] Downloading models (single-thread)...
if "%USE_MODEL_ARG%"=="1" goto model_target_selected
if /I "%TARGET%"=="all" goto model_target_default
if /I "%TARGET%"=="soma" goto model_target_soma
if /I "%TARGET%"=="nf4" goto model_target_done
echo [ERROR] Unknown --target: %TARGET%
exit /b 1

:model_target_selected
call :resolve_model "%MODEL_NAME%"
if errorlevel 1 exit /b 1
call :ensure_repo "!MODEL_REPO_URL!" "%MODELS_DIR%\!MODEL_DIR_NAME!" "model.safetensors"
if errorlevel 1 exit /b 1
goto model_target_done

:model_target_default
call :resolve_model "%MODEL_NAME%"
if errorlevel 1 exit /b 1
call :ensure_repo "!MODEL_REPO_URL!" "%MODELS_DIR%\!MODEL_DIR_NAME!" "model.safetensors"
if errorlevel 1 exit /b 1
goto model_target_done

:model_target_soma
call :resolve_model "Kimodo-SOMA-RP-v1"
if errorlevel 1 exit /b 1
call :ensure_repo "!MODEL_REPO_URL!" "%MODELS_DIR%\!MODEL_DIR_NAME!" "model.safetensors"
if errorlevel 1 exit /b 1
goto model_target_done

:model_target_done

if "%HIGHVRAM%"=="1" (
  echo [STEP] highvram mode enabled: full text-encoder assets
  call :ensure_repo "%META_LLAMA_REPO_URL%" "%MODELS_DIR%\Meta-Llama-3-8B-Instruct" "model.safetensors.index.json" || exit /b 1
  call :ensure_repo_any "%LLM2VEC_PEFT_REPO_URL%" "%MODELS_DIR%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised" "adapter_model.safetensors" "model.safetensors" || exit /b 1
) else (
  call :ensure_repo "%LLM2VEC_NF4_REPO_URL%" "%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4" "model.safetensors" || exit /b 1
)

echo [OK] download_model complete.
exit /b 0

:ensure_git_and_lfs
if exist "%GIT_INSTALLER_PS1%" (
  set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
  if not exist "!POWERSHELL_EXE!" set "POWERSHELL_EXE=powershell"
  "!POWERSHELL_EXE!" -NoProfile -ExecutionPolicy Bypass -File "%GIT_INSTALLER_PS1%" -RootDir "%ROOT_DIR%" -EmitEnvFile "%GIT_ENV_TMP%" -Quiet
  if errorlevel 1 (
    echo [ERROR] Failed to prepare git/git-lfs from installer script.
    exit /b 1
  )
  if exist "%GIT_ENV_TMP%" call "%GIT_ENV_TMP%"
)
call :ensure_git || exit /b 1
call :ensure_git_lfs || exit /b 1
exit /b 0

:ensure_repo_any
set "ANY_REPO_URL=%~1"
set "ANY_DEST_DIR=%~2"
set "ANY_REQ_A=%~3"
set "ANY_REQ_B=%~4"
call :ensure_repo "%ANY_REPO_URL%" "%ANY_DEST_DIR%" "%ANY_REQ_A%"
if not errorlevel 1 exit /b 0
call :ensure_repo "%ANY_REPO_URL%" "%ANY_DEST_DIR%" "%ANY_REQ_B%"
if not errorlevel 1 exit /b 0
echo [ERROR] Missing required files after sync: %ANY_DEST_DIR%
echo [ERROR] Need one of: %ANY_REQ_A% or %ANY_REQ_B%
exit /b 1

:resolve_model
set "RAW_MODEL=%~1"
set "REQ_MODEL=%RAW_MODEL%"
if not defined REQ_MODEL (
  echo [ERROR] Empty --model.
  exit /b 1
)
if /I "%REQ_MODEL%"=="soma" set "REQ_MODEL=Kimodo-SOMA-RP-v1"
if /I "%REQ_MODEL%"=="soma-rp" set "REQ_MODEL=Kimodo-SOMA-RP-v1"
if /I "%REQ_MODEL%"=="kimodo-soma-rp" set "REQ_MODEL=Kimodo-SOMA-RP-v1"
if /I "%REQ_MODEL%"=="g1" set "REQ_MODEL=Kimodo-G1-RP-v1"
if /I "%REQ_MODEL%"=="g1-rp" set "REQ_MODEL=Kimodo-G1-RP-v1"
if /I "%REQ_MODEL%"=="kimodo-g1-rp" set "REQ_MODEL=Kimodo-G1-RP-v1"
if /I "%REQ_MODEL%"=="soma-seed" set "REQ_MODEL=Kimodo-SOMA-SEED-v1"
if /I "%REQ_MODEL%"=="kimodo-soma-seed" set "REQ_MODEL=Kimodo-SOMA-SEED-v1"
if /I "%REQ_MODEL%"=="g1-seed" set "REQ_MODEL=Kimodo-G1-SEED-v1"
if /I "%REQ_MODEL%"=="kimodo-g1-seed" set "REQ_MODEL=Kimodo-G1-SEED-v1"
if /I "%REQ_MODEL%"=="smplx" set "REQ_MODEL=Kimodo-SMPLX-RP-v1"
if /I "%REQ_MODEL%"=="smplx-rp" set "REQ_MODEL=Kimodo-SMPLX-RP-v1"
if /I "%REQ_MODEL%"=="kimodo-smplx-rp" set "REQ_MODEL=Kimodo-SMPLX-RP-v1"

set "MODEL_DIR_NAME=%REQ_MODEL%"
set "REPO_NAME=%REQ_MODEL%"
if /I "%REQ_MODEL%"=="Kimodo-SOMA-RP-v1" set "REPO_NAME=Kimodo-SOMA-RP-v1.1"

if not "%REQ_MODEL:~0,7%"=="Kimodo-" (
  echo [ERROR] Unsupported --model: %RAW_MODEL%
  echo [ERROR] Example: Kimodo-SOMA-RP-v1, Kimodo-G1-RP-v1, Kimodo-SMPLX-RP-v1
  exit /b 1
)

set "MODEL_REPO_URL=https://www.modelscope.cn/nv-community/%REPO_NAME%.git"
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
call :normalize_repo_url "%REPO_URL%"
set "REPO_URL=%NORMALIZED_REPO_URL%"

if "%FORCE_SYNC%"=="0" if exist "%DEST_DIR%\%REQ_FILE%" (
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

:normalize_repo_url
set "RAW_URL=%~1"
set "NORMALIZED_REPO_URL=%RAW_URL%"

echo %RAW_URL% | findstr /I /C:"modelscope.cn/models/" >nul
if not errorlevel 1 (
  set "TMP_URL=!RAW_URL:https://www.modelscope.cn/models/=!"
  set "TMP_URL=!TMP_URL:http://www.modelscope.cn/models/=!"
  set "TMP_URL=!TMP_URL:/models/=!"
  set "TMP_URL=!TMP_URL:.git=!"
  set "NORMALIZED_REPO_URL=https://www.modelscope.cn/!TMP_URL!.git"
  exit /b 0
)

if /I "%RAW_URL:~0,28%"=="https://www.modelscope.cn/" (
  echo %RAW_URL% | findstr /I /C:".git" >nul
  if errorlevel 1 set "NORMALIZED_REPO_URL=%RAW_URL%.git"
  exit /b 0
)

if /I "%RAW_URL:~0,24%"=="https://huggingface.co/" (
  echo %RAW_URL% | findstr /I /C:".git" >nul
  if errorlevel 1 set "NORMALIZED_REPO_URL=%RAW_URL%.git"
  exit /b 0
)

exit /b 0

:prepare_repo
set "REPO_DIR=%~1"
if "%UNLOCK_STALE%"=="1" call :rotate_lock "%REPO_DIR%"
git -C "%REPO_DIR%" rev-parse --verify HEAD >nul 2>nul
if not errorlevel 1 exit /b 0
if exist "%REPO_DIR%\model.safetensors" (
  echo [WARN] Existing non-git model directory found, keep local files: %REPO_DIR%
  exit /b 0
)
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
