@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "LOG_DIR=%ROOT_DIR%\log"
set "MODELS_DIR=%ROOT_DIR%\models"
set "RECOVERY_FLAG_DIR=%ROOT_DIR%\archive\recovery_flags"
set "OUTPUT_MODE=console"
set "LOG_PATH=%LOG_DIR%\download_model.log"
set "UNLOCK_STALE=0"
set "FORCE_SYNC=0"
set "DOWNLOAD_GGUF=%KIMODO_DOWNLOAD_GGUF%"
if not defined DOWNLOAD_GGUF set "DOWNLOAD_GGUF=1"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "HIGHVRAM=0"
set "MODEL_DIR_NAME="
set "MODEL_REPO_URL="
set "MODEL_REPO_URL_FALLBACK="
set "RESOLVE_MODEL_ALIAS_BAT=%ROOT_DIR%\bash\resolve_model_alias.bat"
set "LLM2VEC_NF4_REPO_URL=https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git"
set "LLM2VEC_NF4_REPO_URL_FALLBACK=https://huggingface.co/Aero-Ex/KIMODO-Meta3_llm2vec_NF4"
set "GGUF_REPO_URL=https://www.modelscope.cn/LLM-Research/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF.git"
set "GGUF_REPO_URL_FALLBACK=https://huggingface.co/Aero-Ex/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF"
set "META_LLAMA_REPO_URL=https://www.modelscope.cn/models/LLM-Research/Meta-Llama-3-8B-Instruct"
set "LLM2VEC_PEFT_REPO_URL=https://www.modelscope.cn/models/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
set "INJECT_ONCE=0"

if defined KIMODO_LLM2VEC_NF4_REPO_URL set "LLM2VEC_NF4_REPO_URL=%KIMODO_LLM2VEC_NF4_REPO_URL%"
if defined KIMODO_LLM2VEC_NF4_REPO_URL_FALLBACK set "LLM2VEC_NF4_REPO_URL_FALLBACK=%KIMODO_LLM2VEC_NF4_REPO_URL_FALLBACK%"
if defined KIMODO_GGUF_REPO_URL set "GGUF_REPO_URL=%KIMODO_GGUF_REPO_URL%"
if defined KIMODO_GGUF_REPO_URL_FALLBACK set "GGUF_REPO_URL_FALLBACK=%KIMODO_GGUF_REPO_URL_FALLBACK%"
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
if /I "%~1"=="--model" (
  set "MODEL_NAME=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--download-gguf" (
  set "DOWNLOAD_GGUF=1"
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
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
if not exist "%MODELS_DIR%" mkdir "%MODELS_DIR%" >nul 2>nul

if defined KIMODO_TEST_SCENARIO_NAME echo [TEST] scenario=%KIMODO_TEST_SCENARIO_NAME%

call :ensure_git_and_lfs || exit /b 1

echo [STEP] Downloading models (single-thread)...
if not exist "%RESOLVE_MODEL_ALIAS_BAT%" (
  echo [ERROR] Missing model alias resolver: %RESOLVE_MODEL_ALIAS_BAT%
  exit /b 1
)
call "%RESOLVE_MODEL_ALIAS_BAT%" "%MODEL_NAME%"
if errorlevel 1 exit /b 1
set "MODEL_NAME=%MODEL_NAME%"
set "MODEL_DIR_NAME=%MODEL_DIR_NAME%"
set "MODEL_REPO_URL=https://www.modelscope.cn/nv-community/%MODEL_REPO_NAME%.git"
set "MODEL_REPO_URL_FALLBACK="
if /I "%MODEL_REPO_NAME%"=="Kimodo-SOMA-RP-v1.1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1"
if /I "%MODEL_REPO_NAME%"=="Kimodo-SMPLX-RP-v1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-SMPLX-RP-v1"
if /I "%MODEL_REPO_NAME%"=="Kimodo-G1-RP-v1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-G1-RP-v1"
if /I "%MODEL_REPO_NAME%"=="Kimodo-SOMA-SEED-v1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1"
if /I "%MODEL_REPO_NAME%"=="Kimodo-SOMA-SEED-v1.1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1.1"
if /I "%MODEL_REPO_NAME%"=="Kimodo-G1-SEED-v1" set "MODEL_REPO_URL_FALLBACK=https://huggingface.co/nvidia/Kimodo-G1-SEED-v1"
call :ensure_repo_with_fallback "%MODEL_REPO_URL%" "%MODEL_REPO_URL_FALLBACK%" "%MODELS_DIR%\%MODEL_DIR_NAME%" "model.safetensors" "*"
if errorlevel 1 exit /b 1

if "%HIGHVRAM%"=="1" (
  echo [STEP] highvram mode enabled: full text-encoder assets
  call :ensure_repo "%META_LLAMA_REPO_URL%" "%MODELS_DIR%\Meta-Llama-3-8B-Instruct" "model.safetensors.index.json" "*" || exit /b 1
  call :ensure_repo_any "%LLM2VEC_PEFT_REPO_URL%" "%MODELS_DIR%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised" "adapter_model.safetensors" "model.safetensors" "*" || exit /b 1
) else (
  call :ensure_repo_with_fallback "%LLM2VEC_NF4_REPO_URL%" "%LLM2VEC_NF4_REPO_URL_FALLBACK%" "%MODELS_DIR%\KIMODO-Meta3_llm2vec_NF4" "model.safetensors" "*" || exit /b 1
)
if /I "%DOWNLOAD_GGUF%"=="1" (
  echo [STEP] CPU gguf mode enabled: downloading GGUF text encoder model
  call :ensure_repo_with_fallback "%GGUF_REPO_URL%" "%GGUF_REPO_URL_FALLBACK%" "%MODELS_DIR%\Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF" ".gguf" "*" || exit /b 1
)

echo [OK] download_model complete.
exit /b 0

:ensure_git_and_lfs
call :ensure_git || exit /b 1
call :ensure_git_lfs || exit /b 1
exit /b 0

:ensure_repo_any
set "ANY_REPO_URL=%~1"
set "ANY_DEST_DIR=%~2"
set "ANY_REQ_A=%~3"
set "ANY_REQ_B=%~4"
set "ANY_LFS_INCLUDE=%~5"
call :ensure_repo "%ANY_REPO_URL%" "%ANY_DEST_DIR%" "%ANY_REQ_A%" "%ANY_LFS_INCLUDE%"
if not errorlevel 1 exit /b 0
call :ensure_repo "%ANY_REPO_URL%" "%ANY_DEST_DIR%" "%ANY_REQ_B%" "%ANY_LFS_INCLUDE%"
if not errorlevel 1 exit /b 0
echo [ERROR] Missing required files after sync: %ANY_DEST_DIR%
echo [ERROR] Need one of: %ANY_REQ_A% or %ANY_REQ_B%
exit /b 1

:ensure_repo_with_fallback
set "PRIMARY_REPO_URL=%~1"
set "FALLBACK_REPO_URL=%~2"
set "FALLBACK_DEST_DIR=%~3"
set "FALLBACK_REQ_FILE=%~4"
set "FALLBACK_LFS_INCLUDE=%~5"
call :ensure_repo "%PRIMARY_REPO_URL%" "%FALLBACK_DEST_DIR%" "%FALLBACK_REQ_FILE%" "%FALLBACK_LFS_INCLUDE%"
if not errorlevel 1 exit /b 0
if not defined FALLBACK_REPO_URL exit /b 1
echo [WARN] Primary repo failed, fallback to: %FALLBACK_REPO_URL%
call :ensure_repo "%FALLBACK_REPO_URL%" "%FALLBACK_DEST_DIR%" "%FALLBACK_REQ_FILE%" "%FALLBACK_LFS_INCLUDE%"
if errorlevel 1 exit /b 1
echo [OK] Fallback repo succeeded: %FALLBACK_REPO_URL%
exit /b 0

:ensure_git
set "GIT_HINT=%ROOT_DIR%\program\exe\git\cmd"
if exist "%GIT_HINT%\git.exe" (
  set "PATH=%GIT_HINT%;%PATH%"
  git --version >nul 2>nul
  if not errorlevel 1 exit /b 0
)
echo [ERROR] git not found.
echo [ERROR] Place local git at: %GIT_HINT%\git.exe
exit /b 1

:ensure_git_lfs
set "LFS_HINT=%ROOT_DIR%\program\exe\git\mingw32\bin"
if exist "%LFS_HINT%\git-lfs.exe" set "PATH=%LFS_HINT%;%PATH%"
git lfs version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git-lfs not found.
  echo [ERROR] Place local git-lfs at: %LFS_HINT%\git-lfs.exe
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
set "LFS_INCLUDE=%~4"
if not defined LFS_INCLUDE set "LFS_INCLUDE=%REQ_FILE%"
call :normalize_repo_url "%REPO_URL%"
set "REPO_URL=%NORMALIZED_REPO_URL%"

call :should_inject_once "download_net_bad" "KIMODO_TEST_INJECT_DOWNLOAD_NET_BAD_ONCE"
if "!INJECT_ONCE!"=="1" (
  echo [TEST] Injected download network failure once: %DEST_DIR%
  exit /b 93
)

call :should_inject_once "download_abort" "KIMODO_TEST_INJECT_DOWNLOAD_ABORT_ONCE"
if "!INJECT_ONCE!"=="1" (
  echo [TEST] Injected download interrupt once before sync: %DEST_DIR%
  exit /b 92
)

if "%FORCE_SYNC%"=="0" (
  if /I "%REQ_FILE%"==".gguf" (
    if exist "%DEST_DIR%" (
      call :ensure_gguf_presence "%DEST_DIR%"
      if not errorlevel 1 (
        echo [INFO] Skip existing gguf model: %DEST_DIR%
        call :inject_missing_after_download "%DEST_DIR%" "%REQ_FILE%"
        exit /b 0
      )
      echo [WARN] Existing GGUF directory has no .gguf files, forcing sync: %DEST_DIR%
    )
  ) else (
    if exist "%DEST_DIR%\%REQ_FILE%" (
      echo [INFO] Skip existing model: %DEST_DIR%
      call :validate_repo_safetensors "%DEST_DIR%" "%REQ_FILE%" "%LFS_INCLUDE%"
      if errorlevel 1 exit /b 1
      call :inject_missing_after_download "%DEST_DIR%" "%REQ_FILE%"
      exit /b 0
    )
  )
)

if exist "%DEST_DIR%" (
  if not exist "%DEST_DIR%\.git" (
    call :backup_dir "%DEST_DIR%" || exit /b 1
  )
)

:ensure_repo_sync
if not exist "%DEST_DIR%" (
  echo [STEP] Cloning %REPO_URL%
  set "GIT_LFS_SKIP_SMUDGE=1"
  git clone "%REPO_URL%" "%DEST_DIR%"
  set "GIT_LFS_SKIP_SMUDGE="
  if errorlevel 1 exit /b 1
) else (
  call :prepare_repo "%DEST_DIR%" || exit /b 1
  echo [STEP] Updating existing repo: %DEST_DIR%
  set "GIT_LFS_SKIP_SMUDGE=1"
  git -C "%DEST_DIR%" pull
  set "GIT_LFS_SKIP_SMUDGE="
  if errorlevel 1 (
    call :backup_dir "%DEST_DIR%" || exit /b 1
    echo [STEP] Re-cloning %REPO_URL%
    set "GIT_LFS_SKIP_SMUDGE=1"
    git clone "%REPO_URL%" "%DEST_DIR%"
    set "GIT_LFS_SKIP_SMUDGE="
    if errorlevel 1 exit /b 1
  )
)

call :prepare_repo "%DEST_DIR%" || exit /b 1
git -C "%DEST_DIR%" lfs pull --include="%LFS_INCLUDE%"
if errorlevel 1 exit /b 1

if /I "%REQ_FILE%"==".gguf" (
  call :ensure_gguf_presence "%DEST_DIR%"
  if errorlevel 1 (
    echo [ERROR] Missing .gguf files after sync: %DEST_DIR%
    exit /b 1
  )
) else (
  if not exist "%DEST_DIR%\%REQ_FILE%" (
    git -C "%DEST_DIR%" checkout HEAD -- "%REQ_FILE%"
    if errorlevel 1 exit /b 1
    git -C "%DEST_DIR%" lfs pull --include="%LFS_INCLUDE%"
    if errorlevel 1 exit /b 1
  )
  if not exist "%DEST_DIR%\%REQ_FILE%" (
    echo [ERROR] Missing %REQ_FILE% after sync: %DEST_DIR%
    exit /b 1
  )
)
call :validate_repo_safetensors "%DEST_DIR%" "%REQ_FILE%" "%LFS_INCLUDE%"
if errorlevel 1 exit /b 1
call :inject_missing_after_download "%DEST_DIR%" "%REQ_FILE%"
exit /b 0

:ensure_gguf_presence
set "GGUF_DIR=%~1"
set "GGUF_COUNT=0"
for /f %%G in ('dir /b /s "%GGUF_DIR%\*.gguf" 2^>nul ^| find /c /v ""') do set "GGUF_COUNT=%%G"
if not defined GGUF_COUNT set "GGUF_COUNT=0"
if "%GGUF_COUNT%"=="0" exit /b 1
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

:validate_repo_safetensors
set "VAL_DEST_DIR=%~1"
set "VAL_REQ_FILE=%~2"
set "VAL_LFS_INCLUDE=%~3"
set "VAL_TARGET=%VAL_DEST_DIR%\%VAL_REQ_FILE%"
if /I not "%VAL_REQ_FILE:~-12%"==".safetensors" exit /b 0
if not exist "%VAL_TARGET%" exit /b 0

call :validate_safetensor "%VAL_TARGET%"
if not errorlevel 1 exit /b 0

echo [WARN] Corrupted safetensor detected: %VAL_TARGET%
if exist "%VAL_TARGET%" (
  set "VAL_BROKEN=%VAL_TARGET%.broken.%RANDOM%%RANDOM%"
  move "%VAL_TARGET%" "%VAL_BROKEN%" >nul
  if errorlevel 1 (
    echo [ERROR] Failed to archive corrupted safetensor: %VAL_TARGET%
    exit /b 1
  )
  echo [WARN] Archived corrupted safetensor: %VAL_BROKEN%
)
git -C "%VAL_DEST_DIR%" checkout HEAD -- "%VAL_REQ_FILE%"
if errorlevel 1 exit /b 1
git -C "%VAL_DEST_DIR%" lfs pull --include="%VAL_LFS_INCLUDE%"
if errorlevel 1 exit /b 1
if not exist "%VAL_TARGET%" (
  echo [ERROR] Missing %VAL_REQ_FILE% after repair sync: %VAL_DEST_DIR%
  exit /b 1
)
call :validate_safetensor "%VAL_TARGET%"
if errorlevel 1 (
  echo [ERROR] safetensors validation still failed after one-time repair: %VAL_TARGET%
  exit /b 1
)
echo [OK] safetensors repaired: %VAL_TARGET%
exit /b 0

:validate_safetensor
set "VAL_FILE=%~1"
if not exist "%VAL_FILE%" exit /b 1
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $f='%VAL_FILE%'; $fs=[IO.File]::Open($f,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); try { $buf=New-Object byte[] 8; $read=$fs.Read($buf,0,8); if($read -lt 8){ throw 'short-header' }; $len=[BitConverter]::ToUInt64($buf,0); if($len -le 0 -or $len -gt 104857600){ throw ('invalid-header-length:' + $len) } } finally { $fs.Close() }" >nul 2>nul
if errorlevel 1 exit /b 1
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

:inject_missing_after_download
set "MISSING_DEST_DIR=%~1"
set "MISSING_REQ_FILE=%~2"
set "MISSING_PATH=%MISSING_DEST_DIR%\%MISSING_REQ_FILE%"
call :should_inject_once "model_missing_after_download" "KIMODO_TEST_INJECT_MODEL_MISSING_AFTER_DOWNLOAD_ONCE"
if not "!INJECT_ONCE!"=="1" exit /b 0
if not exist "%MISSING_PATH%" exit /b 0
set "BROKEN_PATH=%MISSING_PATH%.broken.%RANDOM%%RANDOM%"
move "%MISSING_PATH%" "%BROKEN_PATH%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to inject model missing: %MISSING_PATH%
  exit /b 1
)
echo [TEST] Injected missing model file once: %BROKEN_PATH%
exit /b 0

:should_inject_once
set "INJECT_ONCE=0"
set "ONCE_KEY=%~1"
set "ONCE_SWITCH_NAME=%~2"
set "ONCE_SWITCH_VALUE="
call set "ONCE_SWITCH_VALUE=%%%ONCE_SWITCH_NAME%%%"
if /I not "%ONCE_SWITCH_VALUE%"=="1" exit /b 0
if not exist "%RECOVERY_FLAG_DIR%" mkdir "%RECOVERY_FLAG_DIR%" >nul 2>nul
set "ONCE_FLAG=%RECOVERY_FLAG_DIR%\%ONCE_KEY%.done"
if exist "%ONCE_FLAG%" exit /b 0
> "%ONCE_FLAG%" (
  echo scenario=%KIMODO_TEST_SCENARIO_NAME%
  echo key=%ONCE_KEY%
  echo time=%DATE% %TIME%
)
set "INJECT_ONCE=1"
exit /b 0
