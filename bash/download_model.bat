@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
for %%I in ("%SCRIPT_DIR%\..") do set "ROOT_DIR=%%~fI"
set "LOG_DIR=%ROOT_DIR%\log"
set "MODELS_ROOT=%ROOT_DIR%\models"
set "OUTPUT_MODE=console"
set "LOG_PATH=%LOG_DIR%\download_model.log"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "RUN_DEVICE="
set "CPU_TEXT_ENCODER=gguf"
set "VENV_PY="
set "HIGHVRAM=0"
set "UNLOCK_STALE=0"
set "FORCE_SYNC=0"

:parse_args
if "%~1"=="" goto parsed_args
if /I "%~1"=="--output" (
  if "%~2"=="" (
    call :log_line [ERROR] --output requires a value.
    exit /b 1
  )
  set "OUTPUT_MODE=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--log" (
  if "%~2"=="" (
    call :log_line [ERROR] --log requires a value.
    exit /b 1
  )
  set "LOG_PATH=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--model" (
  if "%~2"=="" (
    call :log_line [ERROR] --model requires a value.
    exit /b 1
  )
  set "MODEL_NAME=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--device" (
  if "%~2"=="" (
    call :log_line [ERROR] --device requires a value.
    exit /b 1
  )
  set "RUN_DEVICE=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--cpu-text-encoder" (
  if "%~2"=="" (
    call :log_line [ERROR] --cpu-text-encoder requires a value.
    exit /b 1
  )
  set "CPU_TEXT_ENCODER=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--venv" (
  if "%~2"=="" (
    call :log_line [ERROR] --venv requires a value.
    exit /b 1
  )
  set "VENV_PY=%~2"
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
if /I "%~1"=="--highvram" (
  set "HIGHVRAM=1"
  shift
  goto parse_args
)
shift
goto parse_args
:parsed_args

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>nul
for %%I in ("%LOG_PATH%") do if not exist "%%~dpI" mkdir "%%~dpI" >nul 2>nul
if not exist "%MODELS_ROOT%" mkdir "%MODELS_ROOT%" >nul 2>nul

set "LOCAL_GIT_CMD=%ROOT_DIR%\program\exe\git\cmd"
set "LOCAL_GIT_LFS=%ROOT_DIR%\program\exe\git\mingw32\bin"
set "GIT_LFS_SKIP_SMUDGE=1"
if not exist "%LOCAL_GIT_CMD%\git.exe" (
  call :log_line [ERROR] Missing local git: %LOCAL_GIT_CMD%\git.exe
  exit /b 1
)
if not exist "%LOCAL_GIT_LFS%\git-lfs.exe" (
  call :log_line [ERROR] Missing local git-lfs: %LOCAL_GIT_LFS%\git-lfs.exe
  exit /b 1
)
set "PATH=%LOCAL_GIT_CMD%;%LOCAL_GIT_LFS%;%PATH%"

set "MODEL_CANON=%MODEL_NAME%"
if /I "%MODEL_CANON%"=="SOMA" set "MODEL_CANON=Kimodo-SOMA-RP-v1"
if /I "%MODEL_CANON%"=="SOMA-RP" set "MODEL_CANON=Kimodo-SOMA-RP-v1"
if /I "%MODEL_CANON%"=="KIMODO-SOMA-RP" set "MODEL_CANON=Kimodo-SOMA-RP-v1"
if /I "%MODEL_CANON%"=="G1" set "MODEL_CANON=Kimodo-G1-RP-v1"
if /I "%MODEL_CANON%"=="G1-RP" set "MODEL_CANON=Kimodo-G1-RP-v1"
if /I "%MODEL_CANON%"=="KIMODO-G1-RP" set "MODEL_CANON=Kimodo-G1-RP-v1"
if /I "%MODEL_CANON%"=="SOMA-SEED" set "MODEL_CANON=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_CANON%"=="KIMODO-SOMA-SEED" set "MODEL_CANON=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_CANON%"=="G1-SEED" set "MODEL_CANON=Kimodo-G1-SEED-v1"
if /I "%MODEL_CANON%"=="KIMODO-G1-SEED" set "MODEL_CANON=Kimodo-G1-SEED-v1"
if /I "%MODEL_CANON%"=="SMPLX" set "MODEL_CANON=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_CANON%"=="SMPLX-RP" set "MODEL_CANON=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_CANON%"=="KIMODO-SMPLX-RP" set "MODEL_CANON=Kimodo-SMPLX-RP-v1"
if /I not "%MODEL_CANON:~0,7%"=="Kimodo-" (
  call :log_line [ERROR] Unsupported model alias: %MODEL_NAME%
  exit /b 1
)
set "MODEL_DIR_NAME=%MODEL_CANON%"
set "MODEL_REPO_NAME=%MODEL_CANON%"
if /I "%MODEL_CANON%"=="Kimodo-SOMA-RP-v1" set "MODEL_REPO_NAME=Kimodo-SOMA-RP-v1.1"

set "MODEL_TARGET=%MODELS_ROOT%\%MODEL_DIR_NAME%"
set "MODEL_PRIMARY=https://www.modelscope.cn/nv-community/%MODEL_REPO_NAME%.git"
set "MODEL_FALLBACK=https://huggingface.co/nvidia/%MODEL_REPO_NAME%.git"
set "MODEL_VALIDATE=model"

set "GGUF_TARGET=%MODELS_ROOT%\Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF"
set "GGUF_PRIMARY=https://www.modelscope.cn/LLM-Research/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF.git"
set "GGUF_FALLBACK=https://huggingface.co/Aero-Ex/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF.git"
set "GGUF_VALIDATE=gguf"

set "NF4_TARGET=%MODELS_ROOT%\KIMODO-Meta3_llm2vec_NF4"
set "NF4_PRIMARY=https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git"
set "NF4_FALLBACK=https://huggingface.co/Aero-Ex/KIMODO-Meta3_llm2vec_NF4.git"
set "NF4_VALIDATE=nf4"

set "FULL_BASE_TARGET=%MODELS_ROOT%\Meta-Llama-3-8B-Instruct"
set "FULL_BASE_PRIMARY=https://www.modelscope.cn/LLM-Research/Meta-Llama-3-8B-Instruct.git"
set "FULL_BASE_FALLBACK="
set "FULL_BASE_VALIDATE=full_base"

set "FULL_PEFT_TARGET=%MODELS_ROOT%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
set "FULL_PEFT_PRIMARY=https://www.modelscope.cn/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised.git"
set "FULL_PEFT_FALLBACK="
set "FULL_PEFT_VALIDATE=full_peft"

set "VRAM_MB=0"
where nvidia-smi >nul 2>nul
if not errorlevel 1 (
  for /f "tokens=* delims= " %%A in ('nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2^>nul') do (
    set "VRAM_CUR=%%A"
    set /a VRAM_CUR=VRAM_CUR >nul 2>nul
    if not errorlevel 1 if !VRAM_CUR! gtr !VRAM_MB! set "VRAM_MB=!VRAM_CUR!"
  )
)
set "ENCODER_KIND=gguf"
if !VRAM_MB! geq 6144 (
  if /I "%HIGHVRAM%"=="1" (
    set "ENCODER_KIND=full"
  ) else (
    set "ENCODER_KIND=nf4"
  )
)

call :log_line [INFO] model=%MODEL_CANON% highvram=%HIGHVRAM% output=%OUTPUT_MODE%
call :log_line [INFO] vram_mb=%VRAM_MB% encoder=%ENCODER_KIND%

call :sync_repo "main model" "%MODEL_TARGET%" "%MODEL_PRIMARY%" "%MODEL_FALLBACK%" "%MODEL_VALIDATE%"
if errorlevel 1 exit /b 1

if /I "%ENCODER_KIND%"=="gguf" (
  call :sync_repo "GGUF text encoder" "%GGUF_TARGET%" "%GGUF_PRIMARY%" "%GGUF_FALLBACK%" "%GGUF_VALIDATE%"
  if errorlevel 1 exit /b 1
) else (
  if /I "%ENCODER_KIND%"=="nf4" (
    call :sync_repo "NF4 text encoder" "%NF4_TARGET%" "%NF4_PRIMARY%" "%NF4_FALLBACK%" "%NF4_VALIDATE%"
    if errorlevel 1 exit /b 1
  ) else (
    call :sync_repo "full text encoder base" "%FULL_BASE_TARGET%" "%FULL_BASE_PRIMARY%" "%FULL_BASE_FALLBACK%" "%FULL_BASE_VALIDATE%"
    if errorlevel 1 exit /b 1
    call :sync_repo "full text encoder peft" "%FULL_PEFT_TARGET%" "%FULL_PEFT_PRIMARY%" "%FULL_PEFT_FALLBACK%" "%FULL_PEFT_VALIDATE%"
    if errorlevel 1 exit /b 1
  )
)

call :log_line [OK] download_model complete.
exit /b 0

:log_line
setlocal EnableDelayedExpansion
set "LOG_MESSAGE=%*"
if /I "%OUTPUT_MODE%"=="file" (
  >> "%LOG_PATH%" echo(!LOG_MESSAGE!
) else (
  echo(!LOG_MESSAGE!
)
endlocal & exit /b 0

:archive_path
setlocal EnableDelayedExpansion
set "ARCHIVE_TARGET=%~1"
if not exist "!ARCHIVE_TARGET!" (
  endlocal & exit /b 0
)
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
if not exist "!RECYCLE_DIR!" mkdir "!RECYCLE_DIR!" >nul 2>nul
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%RECYCLE_DIR%\%BASE%.%TS%.%RANDOM%%RANDOM%"
move "!ARCHIVE_TARGET!" "!DEST!" >nul 2>nul
endlocal & exit /b 0

:validate_repo
setlocal EnableDelayedExpansion
set "VAL_TARGET=%~1"
set "VAL_KIND=%~2"
set "VAL_OK=0"

if /I "%VAL_KIND%"=="model" (
  if exist "!VAL_TARGET!\model.safetensors" (
    for %%I in ("!VAL_TARGET!\model.safetensors") do (
      if %%~zI GTR 1024 set "VAL_OK=1"
    )
  )
) else if /I "%VAL_KIND%"=="gguf" (
  for /f "delims=" %%G in ('dir /b /s "!VAL_TARGET!\*.gguf" 2^>nul') do (
    for %%I in ("%%G") do (
      if %%~zI GTR 1024 set "VAL_OK=1"
    )
  )
) else if /I "%VAL_KIND%"=="nf4" (
  if exist "!VAL_TARGET!\model.safetensors" (
    for %%I in ("!VAL_TARGET!\model.safetensors") do (
      if %%~zI GTR 1024 set "VAL_OK=1"
    )
  )
) else if /I "%VAL_KIND%"=="full_base" (
  if exist "!VAL_TARGET!\model.safetensors.index.json" (
    set "VAL_OK=1"
  ) else (
    if exist "!VAL_TARGET!\model.safetensors" (
      for %%I in ("!VAL_TARGET!\model.safetensors") do (
        if %%~zI GTR 1024 set "VAL_OK=1"
      )
    )
  )
) else if /I "%VAL_KIND%"=="full_peft" (
  if exist "!VAL_TARGET!\adapter_model.safetensors" (
    for %%I in ("!VAL_TARGET!\adapter_model.safetensors") do (
      if %%~zI GTR 1024 set "VAL_OK=1"
    )
  ) else (
    if exist "!VAL_TARGET!\model.safetensors" (
      for %%I in ("!VAL_TARGET!\model.safetensors") do (
        if %%~zI GTR 1024 set "VAL_OK=1"
      )
    )
  )
)

if "!VAL_OK!"=="1" (
  endlocal & exit /b 0
)
endlocal & exit /b 1

:sync_repo
setlocal EnableDelayedExpansion
set "SYNC_KIND=%~1"
set "SYNC_TARGET=%~2"
set "SYNC_PRIMARY=%~3"
set "SYNC_FALLBACK=%~4"
set "SYNC_VALIDATE=%~5"
set "SYNC_FIRST_URL=%SYNC_PRIMARY%"
set "SYNC_SECOND_URL="
set "SYNC_CAN_PULL=0"
set "SYNC_DONE=0"
set "SYNC_RETRY_CLEAN=0"

ping -n 1 -w 1000 www.modelscope.cn >nul 2>nul
if errorlevel 1 (
  if defined SYNC_FALLBACK (
    set "SYNC_FIRST_URL=%SYNC_FALLBACK%"
    set "SYNC_SECOND_URL=%SYNC_PRIMARY%"
    call :log_line [WARN] !SYNC_KIND! primary site unreachable, using fallback first.
  ) else (
    call :log_line [WARN] !SYNC_KIND! primary site unreachable, no fallback configured.
  )
) else (
  if defined SYNC_FALLBACK set "SYNC_SECOND_URL=%SYNC_FALLBACK%"
)

if exist "!SYNC_TARGET!" (
  if /I "%FORCE_SYNC%"=="1" (
    call :archive_path "!SYNC_TARGET!"
  ) else (
    call :validate_repo "!SYNC_TARGET!" "!SYNC_VALIDATE!"
    if not errorlevel 1 (
      call :log_line [INFO] !SYNC_KIND! already present, skip sync.
      endlocal & exit /b 0
    )
    if exist "!SYNC_TARGET!\.git" (
      set "SYNC_CAN_PULL=1"
      if /I "%UNLOCK_STALE%"=="1" if exist "!SYNC_TARGET!\.git\index.lock" (
        move "!SYNC_TARGET!\.git\index.lock" "!SYNC_TARGET!\.git\index.lock.stale.%RANDOM%%RANDOM%" >nul 2>nul
      )
    ) else (
      call :archive_path "!SYNC_TARGET!"
    )
  )
)

for %%A in (1 2) do (
  if "!SYNC_DONE!"=="0" (
    if "!SYNC_RETRY_CLEAN!"=="1" if exist "!SYNC_TARGET!" (
      call :archive_path "!SYNC_TARGET!"
      set "SYNC_RETRY_CLEAN=0"
    )

    set "SYNC_URL="
    if "%%A"=="1" set "SYNC_URL=!SYNC_FIRST_URL!"
    if "%%A"=="2" set "SYNC_URL=!SYNC_SECOND_URL!"

    if defined SYNC_URL (
      if "!SYNC_CAN_PULL!"=="1" (
        if "%%A"=="1" (
          call :log_line [STEP] Updating !SYNC_KIND!...
          if /I "%OUTPUT_MODE%"=="file" (
            git -C "!SYNC_TARGET!" pull >>"%LOG_PATH%" 2>&1
          ) else (
            git -C "!SYNC_TARGET!" pull
          )
          set "SYNC_RC=!ERRORLEVEL!"
          if "!SYNC_RC!"=="0" (
            if /I "%OUTPUT_MODE%"=="file" (
              git -C "!SYNC_TARGET!" lfs pull --include=* >>"%LOG_PATH%" 2>&1
            ) else (
              git -C "!SYNC_TARGET!" lfs pull --include=*
            )
            set "SYNC_RC=!ERRORLEVEL!"
            if "!SYNC_RC!"=="0" (
              call :validate_repo "!SYNC_TARGET!" "!SYNC_VALIDATE!"
              if not errorlevel 1 set "SYNC_DONE=1"
            )
          )
          if "!SYNC_DONE!"=="0" (
            if exist "!SYNC_TARGET!" call :archive_path "!SYNC_TARGET!"
            set "SYNC_CAN_PULL=0"
            set "SYNC_RETRY_CLEAN=0"
          )
        ) else (
          call :log_line [STEP] Cloning !SYNC_KIND!...
          if /I "%OUTPUT_MODE%"=="file" (
            git clone --depth 1 "!SYNC_URL!" "!SYNC_TARGET!" >>"%LOG_PATH%" 2>&1
          ) else (
            git clone --depth 1 "!SYNC_URL!" "!SYNC_TARGET!"
          )
          set "SYNC_RC=!ERRORLEVEL!"
          if "!SYNC_RC!"=="0" (
            if /I "%OUTPUT_MODE%"=="file" (
              git -C "!SYNC_TARGET!" lfs pull --include=* >>"%LOG_PATH%" 2>&1
            ) else (
              git -C "!SYNC_TARGET!" lfs pull --include=*
            )
            set "SYNC_RC=!ERRORLEVEL!"
            if "!SYNC_RC!"=="0" (
              call :validate_repo "!SYNC_TARGET!" "!SYNC_VALIDATE!"
              if not errorlevel 1 set "SYNC_DONE=1"
            )
          )
          if "!SYNC_DONE!"=="0" set "SYNC_RETRY_CLEAN=1"
        )
      ) else (
        call :log_line [STEP] Cloning !SYNC_KIND!...
        if /I "%OUTPUT_MODE%"=="file" (
          git clone --depth 1 "!SYNC_URL!" "!SYNC_TARGET!" >>"%LOG_PATH%" 2>&1
        ) else (
          git clone --depth 1 "!SYNC_URL!" "!SYNC_TARGET!"
        )
        set "SYNC_RC=!ERRORLEVEL!"
        if "!SYNC_RC!"=="0" (
          if /I "%OUTPUT_MODE%"=="file" (
            git -C "!SYNC_TARGET!" lfs pull --include=* >>"%LOG_PATH%" 2>&1
          ) else (
            git -C "!SYNC_TARGET!" lfs pull --include=*
          )
          set "SYNC_RC=!ERRORLEVEL!"
          if "!SYNC_RC!"=="0" (
            call :validate_repo "!SYNC_TARGET!" "!SYNC_VALIDATE!"
            if not errorlevel 1 set "SYNC_DONE=1"
          )
        )
        if "!SYNC_DONE!"=="0" set "SYNC_RETRY_CLEAN=1"
      )
    )
  )
)

if "!SYNC_DONE!"=="1" (
  endlocal & exit /b 0
)
call :log_line [ERROR] !SYNC_KIND! sync failed.
endlocal & exit /b 1
