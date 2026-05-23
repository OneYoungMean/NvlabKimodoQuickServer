@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
for /f %%I in ('powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0'; $b=[IO.File]::ReadAllBytes($p); if($b.Length -ge 3 -and $b[0]-eq 239 -and $b[1]-eq 187 -and $b[2]-eq 191){'1'} else {'0'}"') do set "__HAS_BOM=%%I"
if "%__HAS_BOM%"=="1" (
  echo [ERROR] run_server.bat contains UTF-8 BOM. Save as UTF-8 without BOM.
  exit /b 1
)

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "LOG_DIR=%ROOT_DIR%\log"
set "LOG_NAME_RUN_SERVER=run_server.log"
set "LOG_NAME_BRIDGE_SERVER=bridge_server.log"
set "LOG_NAME_BRIDGE_MESSAGE=bridge_message.log"
set "LOG_NAME_SETUP=setup.log"
set "LOG_NAME_DOWNLOAD=download_model.log"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "HIGHVRAM=0"
set "OUTPUT_MODE=console"
set "LOG_PATH=%LOG_DIR%\%LOG_NAME_RUN_SERVER%"
set "BOOTSTRAP_LOG_PATH=%LOG_DIR%\%LOG_NAME_BRIDGE_SERVER%"
set "BRIDGE_MESSAGE_LOG_PATH=%LOG_DIR%\%LOG_NAME_BRIDGE_MESSAGE%"
set "SETUP_BAT=%ROOT_DIR%\bash\setup.bat"
set "DOWNLOAD_BAT=%ROOT_DIR%\bash\download_model.bat"
set "RESOLVE_MODEL_ALIAS_BAT=%ROOT_DIR%\bash\resolve_model_alias.bat"
set "LAUNCH_BRIDGE_PS1=%ROOT_DIR%\bash\launch_bridge.ps1"
set "RUN_SETUP_PHASE_BAT=%ROOT_DIR%\bash\run_setup_phase.bat"
set "RUN_DOWNLOAD_PHASE_BAT=%ROOT_DIR%\bash\run_download_phase.bat"
set "WATCHDOG_BRIDGE_BAT=%ROOT_DIR%\bash\watchdog_bridge.bat"
set "COMMON_ENV_BAT=%ROOT_DIR%\bash\common_env.bat"
set "BRIDGE_PROBE_PS1=%ROOT_DIR%\bash\bridge_probe.ps1"
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup.complete"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "SERVER_STATE=%ROOT_DIR%\.run_server_state"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "SOURCE_ROOT="
set "MODEL_DIR_NAME="
set "MODEL_RUN_NAME="
set "MODELS_ROOT=%KIMODO_MODELS_ROOT%"
set "VENV_PATH_ARG="
set "VENV_PY="
set "USING_EXTERNAL_MODELS=0"
set "USING_EXTERNAL_VENV=0"
set "MODEL_VALIDATE_NEEDS_REPAIR=0"
set "CONFIG_ONLY=%KIMODO_CONFIG_ONLY%"
if not defined CONFIG_ONLY set "CONFIG_ONLY=0"
set "WATCHDOG_INTERVAL_SEC=%KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC%"
if not defined WATCHDOG_INTERVAL_SEC set "WATCHDOG_INTERVAL_SEC=1"
set "WATCHDOG_MAX_FAILS=%KIMODO_WATCHDOG_STARTUP_MAX_FAILS%"
if not defined WATCHDOG_MAX_FAILS set "WATCHDOG_MAX_FAILS=30"
set "WATCHDOG_CONNECT_TIMEOUT_MS=%KIMODO_WATCHDOG_CONNECT_TIMEOUT_MS%"
if not defined WATCHDOG_CONNECT_TIMEOUT_MS set "WATCHDOG_CONNECT_TIMEOUT_MS=800"
set "WATCHDOG_RUNTIME_INTERVAL_SEC=%KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC%"
if not defined WATCHDOG_RUNTIME_INTERVAL_SEC set "WATCHDOG_RUNTIME_INTERVAL_SEC=1"
set "WATCHDOG_IDLE_NOLOG_MAX=%KIMODO_WATCHDOG_IDLE_NOLOG_MAX%"
if not defined WATCHDOG_IDLE_NOLOG_MAX set "WATCHDOG_IDLE_NOLOG_MAX=300"
set "SERVER_WINDOW_STYLE=%KIMODO_SERVER_WINDOW_STYLE%"
if not defined SERVER_WINDOW_STYLE set "SERVER_WINDOW_STYLE=Hidden"
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
if /I "%~1"=="--venv" (
  set "VENV_PATH_ARG=%~2"
  shift
  shift
  goto parse_args
)
if /I "%~1"=="--force-setup" (
  call "%COMMON_ENV_BAT%" :archive_file "%SETUP_SENTINEL%" "%RECYCLE_DIR%"
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
if defined VENV_PATH_ARG (
  call "%COMMON_ENV_BAT%" :resolve_venv_python "%VENV_PATH_ARG%"
  if errorlevel 1 exit /b 1
  set "USING_EXTERNAL_VENV=1"
  echo [INFO] Using external venv python: !VENV_PY!
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

if not exist "%RESOLVE_MODEL_ALIAS_BAT%" (
  echo [ERROR] Missing model alias resolver: %RESOLVE_MODEL_ALIAS_BAT%
  exit /b 1
)
if not exist "%LAUNCH_BRIDGE_PS1%" (
  echo [ERROR] Missing bridge launcher script: %LAUNCH_BRIDGE_PS1%
  exit /b 1
)
if not exist "%RUN_SETUP_PHASE_BAT%" (
  echo [ERROR] Missing setup phase script: %RUN_SETUP_PHASE_BAT%
  exit /b 1
)
if not exist "%RUN_DOWNLOAD_PHASE_BAT%" (
  echo [ERROR] Missing download phase script: %RUN_DOWNLOAD_PHASE_BAT%
  exit /b 1
)
if not exist "%WATCHDOG_BRIDGE_BAT%" (
  echo [ERROR] Missing watchdog script: %WATCHDOG_BRIDGE_BAT%
  exit /b 1
)
if not exist "%COMMON_ENV_BAT%" (
  echo [ERROR] Missing common env script: %COMMON_ENV_BAT%
  exit /b 1
)
if not exist "%BRIDGE_PROBE_PS1%" (
  echo [ERROR] Missing bridge probe script: %BRIDGE_PROBE_PS1%
  exit /b 1
)
call "%RESOLVE_MODEL_ALIAS_BAT%" "%MODEL_NAME%"
if errorlevel 1 exit /b 1
set "MODEL_RUN_NAME=%MODEL_NAME%"

if "%USING_EXTERNAL_VENV%"=="0" (
  if exist "%SETUP_LOCK%" (
    echo [ERROR] setup is running: %SETUP_LOCK%
    exit /b 1
  )
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
if defined VENV_PY set "CUR_SIG=%CUR_SIG%;venv=%VENV_PY%"
set "PREV_SIG="
if exist "%SERVER_STATE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%SERVER_STATE%") do (
    if /I "%%A"=="sig" set "PREV_SIG=%%B"
  )
)

if exist "%PORT_FILE%" (
  if /I "%CONFIG_ONLY%"=="1" (
    echo [INFO] Config-only mode: skip existing server probe/shutdown.
  ) else (
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

call "%RUN_SETUP_PHASE_BAT%" "%ROOT_DIR%" "%OUTPUT_MODE%" "%USING_EXTERNAL_VENV%" "%SETUP_SENTINEL%" "%SETUP_BAT%" "%LOG_DIR%\%LOG_NAME_SETUP%"
if errorlevel 1 exit /b 1

call "%RUN_DOWNLOAD_PHASE_BAT%" "%ROOT_DIR%" "%OUTPUT_MODE%" "%USING_EXTERNAL_MODELS%" "%HIGHVRAM%" "%MODEL_RUN_NAME%" "%MODEL_NAME%" "%DOWNLOAD_BAT%" "%LOG_DIR%\%LOG_NAME_DOWNLOAD%"
if errorlevel 1 exit /b 1

if not defined VENV_PY set "VENV_PY=%SOURCE_ROOT%\.venv\Scripts\python.exe"
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

> "%SERVER_STATE%" (
  echo sig=%CUR_SIG%
  echo model=%MODEL_RUN_NAME%
  echo highvram=%HIGHVRAM%
)

if /I "%CONFIG_ONLY%"=="1" (
  echo [OK] Config-only completed. Bridge not started.
  exit /b 0
)

set "KIMODO_IDLE_TIMEOUT_SEC=600"
if exist "%BRIDGE_PID_FILE%" call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_PID_FILE%" "%RECYCLE_DIR%"

if /I "%OUTPUT_MODE%"=="file" (
  set "LOG_USED=%LOG_PATH%"
  echo [INFO] run_server log: !LOG_USED!
  echo [INFO] bridge server log: %BOOTSTRAP_LOG_PATH%
  echo [INFO] bridge message log: %BRIDGE_MESSAGE_LOG_PATH%
  type nul > "!LOG_USED!"
  if exist "%BOOTSTRAP_LOG_PATH%" call "%COMMON_ENV_BAT%" :archive_file "%BOOTSTRAP_LOG_PATH%" "%RECYCLE_DIR%"
  type nul > "%BOOTSTRAP_LOG_PATH%"
  if exist "%BRIDGE_MESSAGE_LOG_PATH%" call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_MESSAGE_LOG_PATH%" "%RECYCLE_DIR%"
  type nul > "%BRIDGE_MESSAGE_LOG_PATH%"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_BRIDGE_PS1%" ^
  -PythonPath "%VENV_PY%" ^
  -RootDir "%ROOT_DIR%" ^
  -ModelName "%MODEL_RUN_NAME%" ^
  -WindowStyle "%SERVER_WINDOW_STYLE%" ^
  -BridgeLogPath "%BOOTSTRAP_LOG_PATH%" ^
  -BridgeMessageLogPath "%BRIDGE_MESSAGE_LOG_PATH%" ^
  -PidFile "%BRIDGE_PID_FILE%" ^
  -OutputMode "%OUTPUT_MODE%"
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
call "%WATCHDOG_BRIDGE_BAT%" "%ROOT_DIR%" "%SERVER_PID%" "%PORT_FILE%" "%BOOTSTRAP_LOG_PATH%" "%WATCHDOG_INTERVAL_SEC%" "%WATCHDOG_MAX_FAILS%" "%WATCHDOG_CONNECT_TIMEOUT_MS%" "%WATCHDOG_RUNTIME_INTERVAL_SEC%" "%WATCHDOG_IDLE_NOLOG_MAX%"
set "RC=%ERRORLEVEL%"
call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_PID_FILE%" "%RECYCLE_DIR%"
exit /b %RC%

:validate_safetensors_or_repair
call :validate_all_safetensors
if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"

if "%MODEL_VALIDATE_NEEDS_REPAIR%"=="0" exit /b 0
echo [WARN] Detected corrupted safetensors file(s). Attempting one-time model re-sync...
if "%USING_EXTERNAL_MODELS%"=="1" (
  echo [ERROR] External models mode is read-only for auto-repair. Please fix or re-sync: %MODELS_ROOT%
  exit /b 1
)
if "%HIGHVRAM%"=="1" (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\%LOG_NAME_DOWNLOAD%" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram
) else (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%LOG_DIR%\%LOG_NAME_DOWNLOAD%" --unlock-stale --model "%MODEL_RUN_NAME%"
)
if errorlevel 1 (
  echo [ERROR] download_model failed during auto-repair.
  exit /b 1
)

call :validate_all_safetensors
if errorlevel 1 set "MODEL_VALIDATE_NEEDS_REPAIR=1"

if "%MODEL_VALIDATE_NEEDS_REPAIR%"=="1" (
  echo [ERROR] safetensors validation still failed after auto-repair.
  exit /b 1
)
echo [OK] safetensors auto-repair completed.
exit /b 0

:validate_all_safetensors
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

if "%MODEL_VALIDATE_NEEDS_REPAIR%"=="1" exit /b 1
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
  call "%COMMON_ENV_BAT%" :archive_file "%VALIDATE_TARGET_FILE%" "%RECYCLE_DIR%"
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
echo [STEP] Killing previous server process...
set "KILL_PID="
if exist "%BRIDGE_PID_FILE%" (
  for /f "usebackq tokens=* delims=" %%I in ("%BRIDGE_PID_FILE%") do (
    if not defined KILL_PID set "KILL_PID=%%I"
  )
)
if defined KILL_PID (
  call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%KILL_PID%"
  if errorlevel 1 (
    echo [WARN] Ignore stale/non-kimodo bridge pid from .bridge.pid: %KILL_PID%
    set "KILL_PID="
  )
)
if not defined KILL_PID if defined PORT (
  for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='SilentlyContinue'; $p=[int]%PORT%; $c=Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess; if($c){ $c }"`) do (
    if not defined KILL_PID set "KILL_PID=%%I"
  )
  if defined KILL_PID (
    call "%COMMON_ENV_BAT%" :kill_pid_if_kimodo_bridge "%KILL_PID%"
    if errorlevel 1 (
      echo [WARN] Port owner is not kimodo bridge, skip force-kill. pid=%KILL_PID% port=%PORT%
      set "KILL_PID="
    )
  )
)
if exist "%BRIDGE_PID_FILE%" call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_PID_FILE%" "%RECYCLE_DIR%"

set /a WAIT_SEC=0
:wait_old_exit
if not exist "%PORT_FILE%" exit /b 0
ping 127.0.0.1 -n 2 >nul
set /a WAIT_SEC+=1
if !WAIT_SEC! geq 30 (
  echo [WARN] Timeout waiting previous server to stop.
  echo [WARN] Archiving stale serverport and continuing restart.
  call "%COMMON_ENV_BAT%" :archive_file "%PORT_FILE%" "%RECYCLE_DIR%"
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%BRIDGE_PROBE_PS1%" -Host "%PHOST%" -Port %PPORT% -ConnectTimeoutMs %WATCHDOG_CONNECT_TIMEOUT_MS% >nul 2>nul
if errorlevel 1 exit /b 1
exit /b 0



