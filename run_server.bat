@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "LOG_DIR=%ROOT_DIR%\log"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "HIGHVRAM=0"
set "OUTPUT_MODE=console"
set "LOG_PATH=%LOG_DIR%\run_server.log"
set "BOOTSTRAP_LOG_PATH=%LOG_DIR%\bridge_bootstrap_error.log"
set "SETUP_BAT=%ROOT_DIR%\bash\setup.bat"
set "DOWNLOAD_BAT=%ROOT_DIR%\bash\download_model.bat"
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup.complete"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "SERVER_STATE=%ROOT_DIR%\.run_server_state"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "SOURCE_ROOT="
set "MODEL_DIR_NAME="
set "MODEL_RUN_NAME="
set "MODELS_ROOT=%KIMODO_MODELS_ROOT%"
set "CONFIG_ONLY=%KIMODO_CONFIG_ONLY%"
if not defined CONFIG_ONLY set "CONFIG_ONLY=0"
set "USING_EXTERNAL_MODELS=0"
set "MODEL_VALIDATE_NEEDS_REPAIR=0"
set "WATCHDOG_INTERVAL_SEC=3"
set "WATCHDOG_MAX_FAILS=10"
set "WATCHDOG_RUNTIME_INTERVAL_SEC=1"
set "WATCHDOG_IDLE_NOLOG_MAX=300"
set "BRIDGE_PID_FILE=%ROOT_DIR%\.bridge.pid"

:parse_args
if "%~1"=="" goto parsed
if /I "%~1"=="--model" (
  set "MODEL_NAME=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--highvram" (
  set "HIGHVRAM=1"
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
if /I "%~1"=="--models-root" (
  set "MODELS_ROOT=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--force-setup" (
  call :archive_file "%SETUP_SENTINEL%"
  shift
  goto parse_args
)
if /I "%~1"=="--config-only" (
  set "CONFIG_ONLY=1"
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
if not defined MODELS_ROOT set "MODELS_ROOT=%ROOT_DIR%\models"
for %%I in ("%MODELS_ROOT%") do set "MODELS_ROOT=%%~fI"
if /I not "%MODELS_ROOT%"=="%ROOT_DIR%\models" set "USING_EXTERNAL_MODELS=1"
if "%USING_EXTERNAL_MODELS%"=="1" (
  if not exist "%MODELS_ROOT%" (
    echo [ERROR] External models root not found: %MODELS_ROOT%
    exit /b 1
  )
  echo [INFO] Using external models root: %MODELS_ROOT%
) else (
  if not exist "%MODELS_ROOT%" mkdir "%MODELS_ROOT%" >nul 2>nul
  echo [INFO] Using runtime models root: %MODELS_ROOT%
)

call :resolve_model_alias "%MODEL_NAME%"
if errorlevel 1 exit /b 1

if /I "%CONFIG_ONLY%"=="1" (
  echo [INFO] Config-only mode enabled. Setup/download/validation will run; bridge launch is skipped.
)

if exist "%SETUP_LOCK%" (
  echo [ERROR] setup is running: %SETUP_LOCK%
  exit /b 1
)

if /I "%HIGHVRAM%"=="1" (
  set "KIMODO_LLM2VEC_DIR=%MODELS_ROOT%\Meta-Llama-3-8B-Instruct"
  set "TEXT_ENCODERS_DIR=%MODELS_ROOT%"
  set "KIMODO_LLM2VEC_PEFT_DIR=%MODELS_ROOT%\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
) else (
  set "KIMODO_LLM2VEC_DIR=%MODELS_ROOT%\KIMODO-Meta3_llm2vec_NF4"
  set "TEXT_ENCODERS_DIR="
  set "KIMODO_LLM2VEC_PEFT_DIR="
)

set "CUR_SIG=model=%MODEL_RUN_NAME%;highvram=%HIGHVRAM%;models=%MODELS_ROOT%;llm2vec=%KIMODO_LLM2VEC_DIR%"
set "PREV_SIG="
if exist "%SERVER_STATE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%SERVER_STATE%") do (
    if /I "%%A"=="sig" set "PREV_SIG=%%B"
  )
)

if /I not "%CONFIG_ONLY%"=="1" (
  if exist "%PORT_FILE%" (
    if /I not "%PREV_SIG%"=="%CUR_SIG%" (
      echo [STEP] Existing server params differ, stopping previous server...
      call :shutdown_existing
      if errorlevel 1 exit /b 1
    ) else (
      call :probe_existing_server
      if errorlevel 1 (
        echo [WARN] Existing server signature matches, but probe failed. Restarting...
        call :shutdown_existing
        if errorlevel 1 exit /b 1
      ) else (
        echo [INFO] Existing server already running with same params: %CUR_SIG%
        exit /b 0
      )
    )
  )
)

if not exist "%SETUP_SENTINEL%" (
  echo [STEP] setup not found, running setup...
  call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%LOG_DIR%\setup.log"
  if errorlevel 1 exit /b 1
)

if "%USING_EXTERNAL_MODELS%"=="1" (
  echo [STEP] External models mode enabled, skip download_model.
) else (
  echo [STEP] Downloading model assets for model=%MODEL_NAME% highvram=%HIGHVRAM%...
  if "%HIGHVRAM%"=="1" (
    call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram
  ) else (
    call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%"
  )
  if errorlevel 1 exit /b 1
)

set "VENV_PY=%SOURCE_ROOT%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)

if not exist "%MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors" (
  echo [ERROR] Missing model file: %MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors
  exit /b 1
)
if "%HIGHVRAM%"=="1" (
  if not exist "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors.index.json" if not exist "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors" (
    echo [ERROR] Missing Meta-Llama model under %MODELS_ROOT%\Meta-Llama-3-8B-Instruct
    exit /b 1
  )
  if not exist "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors" if not exist "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors" (
    echo [ERROR] Missing LLM2Vec PEFT model under %KIMODO_LLM2VEC_PEFT_DIR%
    exit /b 1
  )
) else (
  if not exist "%KIMODO_LLM2VEC_DIR%\model.safetensors" (
    echo [ERROR] Missing text encoder model: %KIMODO_LLM2VEC_DIR%\model.safetensors
    exit /b 1
  )
)

call :validate_safetensors_or_repair
if errorlevel 1 exit /b 1

set "PYTHONPATH=%SOURCE_ROOT%"
set "KIMODO_ROOT_PATH=%ROOT_DIR%"
set "CHECKPOINT_DIR=%MODELS_ROOT%"
set "LOCAL_CACHE=true"
set "TEXT_ENCODER_MODE=local"
set "TEXT_ENCODER=llm2vec"
set "HF_HOME=%ROOT_DIR%\hf_cache"
set "TRANSFORMERS_CACHE=%HF_HOME%\transformers"
set "HF_HUB_CACHE=%HF_HOME%\hub"
set "HUGGINGFACE_HUB_CACHE=%HF_HOME%\hub"
set "TRANSFORMERS_OFFLINE=1"
set "HF_HUB_OFFLINE=1"
set "HF_DATASETS_OFFLINE=1"
set "PYTHONUNBUFFERED=1"

if not exist "%HF_HOME%" mkdir "%HF_HOME%" >nul 2>nul
if not exist "%TRANSFORMERS_CACHE%" mkdir "%TRANSFORMERS_CACHE%" >nul 2>nul
if not exist "%HUGGINGFACE_HUB_CACHE%" mkdir "%HUGGINGFACE_HUB_CACHE%" >nul 2>nul

if /I "%CONFIG_ONLY%"=="1" (
  echo [OK] Config-only completed. Bridge not started.
  exit /b 0
)

> "%SERVER_STATE%" (
  echo sig=%CUR_SIG%
  echo model=%MODEL_RUN_NAME%
  echo highvram=%HIGHVRAM%
)

set "KIMODO_IDLE_TIMEOUT_SEC=600"
if exist "%BRIDGE_PID_FILE%" call :archive_file "%BRIDGE_PID_FILE%"

if /I "%OUTPUT_MODE%"=="file" (
  set "LOG_USED=%LOG_PATH%"
  echo [INFO] run_server log: !LOG_USED!
  echo [INFO] bridge bootstrap log: %BOOTSTRAP_LOG_PATH%
  type nul > "!LOG_USED!"
  if exist "%BOOTSTRAP_LOG_PATH%" call :archive_file "%BOOTSTRAP_LOG_PATH%"
  type nul > "%BOOTSTRAP_LOG_PATH%"
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $env:KIMODO_BRIDGE_LOG='!LOG_USED!'; $args=@('-u','-m','kimodo.bridge.bridge_server','--model','%MODEL_RUN_NAME%','--kimodo-root','%ROOT_DIR%'); $p=Start-Process -FilePath '%VENV_PY%' -ArgumentList $args -WorkingDirectory '%ROOT_DIR%' -RedirectStandardError '%BOOTSTRAP_LOG_PATH%' -PassThru; $p.Id | Out-File -LiteralPath '%BRIDGE_PID_FILE%' -Encoding ascii;"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $args=@('-u','-m','kimodo.bridge.bridge_server','--model','%MODEL_RUN_NAME%','--kimodo-root','%ROOT_DIR%'); $p=Start-Process -FilePath '%VENV_PY%' -ArgumentList $args -WorkingDirectory '%ROOT_DIR%' -NoNewWindow -PassThru; $p.Id | Out-File -LiteralPath '%BRIDGE_PID_FILE%' -Encoding ascii;"
)
if errorlevel 1 (
  echo [ERROR] Failed to start bridge server process.
  exit /b 1
)

set "SERVER_PID="
for /f "usebackq tokens=* delims=" %%I in ("%BRIDGE_PID_FILE%") do (
  if not defined SERVER_PID set "SERVER_PID=%%I"
)
if not defined SERVER_PID (
  echo [ERROR] Missing bridge PID in %BRIDGE_PID_FILE%
  exit /b 1
)
echo [INFO] Bridge watchdog started. pid=%SERVER_PID% startup_interval=%WATCHDOG_INTERVAL_SEC%s startup_max_fails=%WATCHDOG_MAX_FAILS% runtime_interval=%WATCHDOG_RUNTIME_INTERVAL_SEC%s idle_nolog_max=%WATCHDOG_IDLE_NOLOG_MAX%
call :watchdog_loop "%SERVER_PID%"
set "RC=%ERRORLEVEL%"
call :archive_file "%BRIDGE_PID_FILE%"
exit /b %RC%

:validate_safetensors_or_repair
set "MODEL_VALIDATE_NEEDS_REPAIR=0"
call :validate_safetensor "main-model" "%MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors"
if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"

if "%HIGHVRAM%"=="1" (
  if exist "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors" (
    call :validate_safetensor "meta-llama" "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
  if exist "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors" (
    call :validate_safetensor "llm2vec-peft" "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
  if exist "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors" (
    call :validate_safetensor "llm2vec-peft-model" "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
) else (
  call :validate_safetensor "llm2vec-nf4" "%KIMODO_LLM2VEC_DIR%\model.safetensors"
  if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
)

if "%MODEL_VALIDATE_NEEDS_REPAIR%"=="0" exit /b 0
echo [WARN] Detected corrupted safetensors file(s). Attempting one-time model re-sync...
if "%USING_EXTERNAL_MODELS%"=="1" (
  echo [ERROR] External models mode is read-only for auto-repair. Please fix or re-sync: %MODELS_ROOT%
  exit /b 1
)
if "%HIGHVRAM%"=="1" (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram
) else (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%"
)
if errorlevel 1 (
  echo [ERROR] download_model failed during auto-repair.
  exit /b 1
)

set "MODEL_VALIDATE_NEEDS_REPAIR=0"
call :validate_safetensor "main-model" "%MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors"
if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
if "%HIGHVRAM%"=="1" (
  if exist "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors" (
    call :validate_safetensor "meta-llama" "%MODELS_ROOT%\Meta-Llama-3-8B-Instruct\model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
  if exist "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors" (
    call :validate_safetensor "llm2vec-peft" "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
  if exist "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors" (
    call :validate_safetensor "llm2vec-peft-model" "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors"
    if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
  )
) else (
  call :validate_safetensor "llm2vec-nf4" "%KIMODO_LLM2VEC_DIR%\model.safetensors"
  if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"
)

if "%MODEL_VALIDATE_NEEDS_REPAIR%"=="1" (
  echo [ERROR] safetensors validation still failed after auto-repair.
  exit /b 1
)
echo [OK] safetensors auto-repair completed.
exit /b 0

:validate_safetensor
set "VALIDATE_TARGET_LABEL=%~1"
set "VALIDATE_TARGET_FILE=%~2"
if not exist "%VALIDATE_TARGET_FILE%" (
  echo [ERROR] Missing safetensor for %VALIDATE_TARGET_LABEL%: %VALIDATE_TARGET_FILE%
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $f='%VALIDATE_TARGET_FILE%'; Add-Type -AssemblyName System.IO.Compression.FileSystem; $fs=[IO.File]::Open($f,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); try { $buf=New-Object byte[] 8; $read=$fs.Read($buf,0,8); if($read -lt 8){ throw 'short-header' }; $len=[BitConverter]::ToUInt64($buf,0); if($len -le 0 -or $len -gt 104857600){ throw ('invalid-header-length:' + $len) } } finally { $fs.Close() }" >nul 2>nul
if errorlevel 1 (
  echo [WARN] Corrupted safetensor detected ^(%VALIDATE_TARGET_LABEL%^): %VALIDATE_TARGET_FILE%
  call :archive_file "%VALIDATE_TARGET_FILE%"
  exit /b 1
)
exit /b 0

:resolve_model_alias
set "INPUT_MODEL=%~1"
set "MODEL_RUN_NAME=%INPUT_MODEL%"
if /I "%MODEL_RUN_NAME%"=="soma" set "MODEL_RUN_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_RUN_NAME%"=="soma-rp" set "MODEL_RUN_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_RUN_NAME%"=="kimodo-soma-rp" set "MODEL_RUN_NAME=Kimodo-SOMA-RP-v1"
if /I "%MODEL_RUN_NAME%"=="g1" set "MODEL_RUN_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_RUN_NAME%"=="g1-rp" set "MODEL_RUN_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_RUN_NAME%"=="kimodo-g1-rp" set "MODEL_RUN_NAME=Kimodo-G1-RP-v1"
if /I "%MODEL_RUN_NAME%"=="soma-seed" set "MODEL_RUN_NAME=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_RUN_NAME%"=="kimodo-soma-seed" set "MODEL_RUN_NAME=Kimodo-SOMA-SEED-v1"
if /I "%MODEL_RUN_NAME%"=="g1-seed" set "MODEL_RUN_NAME=Kimodo-G1-SEED-v1"
if /I "%MODEL_RUN_NAME%"=="kimodo-g1-seed" set "MODEL_RUN_NAME=Kimodo-G1-SEED-v1"
if /I "%MODEL_RUN_NAME%"=="smplx" set "MODEL_RUN_NAME=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_RUN_NAME%"=="smplx-rp" set "MODEL_RUN_NAME=Kimodo-SMPLX-RP-v1"
if /I "%MODEL_RUN_NAME%"=="kimodo-smplx-rp" set "MODEL_RUN_NAME=Kimodo-SMPLX-RP-v1"
set "MODEL_DIR_NAME=%MODEL_RUN_NAME%"
if not "%MODEL_RUN_NAME:~0,7%"=="Kimodo-" (
  echo [ERROR] Unsupported --model: %INPUT_MODEL%
  echo [ERROR] Example: Kimodo-SOMA-RP-v1, Kimodo-G1-RP-v1, Kimodo-SMPLX-RP-v1
  exit /b 1
)
exit /b 0

:shutdown_existing
set "HOST="
set "PORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "HOST=%%A"
  set "PORT=%%B"
)
if not defined HOST (
  echo [WARN] serverport exists but unreadable, continue with restart.
  exit /b 0
)
if not defined PORT (
  echo [WARN] serverport exists but missing port, continue with restart.
  exit /b 0
)

echo [STEP] Sending quit to !HOST!:!PORT! ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $h='%HOST%'; $p=[int]%PORT%; $c=New-Object Net.Sockets.TcpClient($h,$p); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $r=New-Object IO.StreamReader($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $null=$r.ReadLine(); $r.Close(); $w.Close(); $s.Close(); $c.Close();" >nul 2>nul

set /a WAIT_SEC=0
:wait_old_exit
if not exist "%PORT_FILE%" exit /b 0
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if !WAIT_SEC! geq 30 (
  echo [WARN] Timeout waiting previous server to stop.
  echo [WARN] Archiving stale serverport and continuing restart.
  call :archive_file "%PORT_FILE%"
  exit /b 0
)
goto wait_old_exit

:probe_existing_server
set "PHOST="
set "PPORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "PHOST=%%A"
  set "PPORT=%%B"
)
if not defined PHOST exit /b 1
if not defined PPORT exit /b 1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $h='%PHOST%'; $p=[int]%PPORT%; $c=$null; try { $c=New-Object Net.Sockets.TcpClient; $iar=$c.BeginConnect($h,$p,$null,$null); if(-not $iar.AsyncWaitHandle.WaitOne(2000)){ throw 'connect-timeout' }; $c.EndConnect($iar); exit 0 } finally { if($c){$c.Close()} }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:watchdog_loop
set "WD_PID=%~1"
set /a WD_FAILS=0
set "WATCHDOG_STARTED_OK=0"
set /a WD_LOG_STALE=0
set "WD_LOG_PATH=%ROOT_DIR%\log\bridge_server.log"
if /I "%OUTPUT_MODE%"=="file" set "WD_LOG_PATH=%LOG_PATH%"
set "WD_LOG_LAST="

:watchdog_tick
call :is_pid_running "%WD_PID%"
if errorlevel 1 (
  if "%WATCHDOG_STARTED_OK%"=="1" (
    echo [INFO] Bridge process exited. pid=%WD_PID%
    exit /b 0
  )
  echo [ERROR] Bridge process exited before becoming responsive. pid=%WD_PID%
  call :print_bootstrap_hint
  exit /b 1
)

if "%WATCHDOG_STARTED_OK%"=="1" goto watchdog_sleep

call :probe_existing_server
if errorlevel 1 (
  set /a WD_FAILS+=1
  echo [INFO] Waiting bridge ready ^(!WD_FAILS!/%WATCHDOG_MAX_FAILS%^)
  if !WD_FAILS! geq %WATCHDOG_MAX_FAILS% (
    echo [ERROR] Bridge unresponsive for %WATCHDOG_MAX_FAILS% checks during startup. Killing pid=%WD_PID%
    call :kill_pid "%WD_PID%"
    call :archive_file "%PORT_FILE%"
    call :print_bootstrap_hint
    exit /b 1
  )
) else (
  echo [INFO] Bridge became responsive.
  set "WATCHDOG_STARTED_OK=1"
  call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_LAST
  if not defined WD_LOG_LAST set "WD_LOG_LAST=0"
  set /a WD_FAILS=0
)

:watchdog_sleep
if "%WATCHDOG_STARTED_OK%"=="1" (
  call :get_file_mtime_epoch "%WD_LOG_PATH%" WD_LOG_NOW
  if not defined WD_LOG_NOW set "WD_LOG_NOW=%WD_LOG_LAST%"
  if "%WD_LOG_NOW%"=="%WD_LOG_LAST%" (
    set /a WD_LOG_STALE+=1
  ) else (
    set /a WD_LOG_STALE=0
    set "WD_LOG_LAST=%WD_LOG_NOW%"
  )
  if !WD_LOG_STALE! geq %WATCHDOG_IDLE_NOLOG_MAX% (
    echo [INFO] No bridge log update for %WATCHDOG_IDLE_NOLOG_MAX% checks. Requesting shutdown...
    call :request_quit
    call :wait_pid_exit_or_kill "%WD_PID%" 10
    call :archive_file "%PORT_FILE%"
    exit /b 0
  )
  call :sleep_seconds "%WATCHDOG_RUNTIME_INTERVAL_SEC%"
) else (
  call :sleep_seconds "%WATCHDOG_INTERVAL_SEC%"
)
goto watchdog_tick

:is_pid_running
set "CHECK_PID=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=Get-Process -Id %CHECK_PID% -ErrorAction SilentlyContinue; if($p){ exit 0 } else { exit 1 }" >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0

:kill_pid
set "KILL_PID_VALUE=%~1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Stop-Process -Id %KILL_PID_VALUE% -Force -ErrorAction SilentlyContinue" >nul 2>nul
exit /b 0

:sleep_seconds
set "SLEEP_SECONDS=%~1"
if not defined SLEEP_SECONDS set "SLEEP_SECONDS=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds %SLEEP_SECONDS%" >nul 2>nul
exit /b 0

:get_file_mtime_epoch
set "MTIME_FILE=%~1"
set "MTIME_OUTVAR=%~2"
set "MTIME_VALUE="
if exist "%MTIME_FILE%" (
  for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%MTIME_FILE%'; if(Test-Path -LiteralPath $p){ [int64]([IO.File]::GetLastWriteTimeUtc($p) - [datetime]'1970-01-01').TotalSeconds }"`) do (
    if not defined MTIME_VALUE set "MTIME_VALUE=%%I"
  )
)
set "%MTIME_OUTVAR%=%MTIME_VALUE%"
exit /b 0

:request_quit
if not exist "%PORT_FILE%" exit /b 0
set "QHOST="
set "QPORT="
for /f "usebackq tokens=1,2 delims=:" %%A in ("%PORT_FILE%") do (
  set "QHOST=%%A"
  set "QPORT=%%B"
)
if not defined QHOST exit /b 0
if not defined QPORT exit /b 0
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue'; $h='%QHOST%'; $p=[int]%QPORT%; $c=New-Object Net.Sockets.TcpClient; $iar=$c.BeginConnect($h,$p,$null,$null); if($iar.AsyncWaitHandle.WaitOne(1500)){ $c.EndConnect($iar); $s=$c.GetStream(); $w=New-Object IO.StreamWriter($s); $w.AutoFlush=$true; $w.WriteLine('{""cmd"":""quit""}'); $w.Close(); $s.Close() }; $c.Close();" >nul 2>nul
exit /b 0

:wait_pid_exit_or_kill
set "WAIT_PID=%~1"
set "WAIT_MAX=%~2"
if not defined WAIT_MAX set "WAIT_MAX=10"
set /a WAIT_COUNT=0
:wait_pid_loop
call :is_pid_running "%WAIT_PID%"
if errorlevel 1 exit /b 0
call :sleep_seconds "1"
set /a WAIT_COUNT+=1
if !WAIT_COUNT! geq %WAIT_MAX% (
  echo [WARN] Bridge did not exit after quit, forcing stop. pid=%WAIT_PID%
  call :kill_pid "%WAIT_PID%"
  exit /b 0
)
goto wait_pid_loop

:print_bootstrap_hint
if exist "%BOOTSTRAP_LOG_PATH%" (
  for %%I in ("%BOOTSTRAP_LOG_PATH%") do (
    if %%~zI gtr 0 (
      echo [ERROR] bootstrap details: %BOOTSTRAP_LOG_PATH%
    ) else (
      echo [WARN] bootstrap log is empty: %BOOTSTRAP_LOG_PATH%
    )
  )
) else (
  echo [WARN] bootstrap log missing: %BOOTSTRAP_LOG_PATH%
)
exit /b 0

:archive_file
set "ARCHIVE_TARGET=%~1"
if not exist "%ARCHIVE_TARGET%" exit /b 0
if not exist "%RECYCLE_DIR%" mkdir "%RECYCLE_DIR%" >nul 2>nul
set "TS=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BASE=%~nx1"
set "DEST=%RECYCLE_DIR%\%BASE%.%TS%.%RANDOM%"
move "%ARCHIVE_TARGET%" "%DEST%" >nul 2>nul
exit /b 0


