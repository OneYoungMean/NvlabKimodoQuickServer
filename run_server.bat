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
set "SETUP_LOCK=%ROOT_DIR%\.setup.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup.complete"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "SOURCE_ROOT="
set "MODEL_DIR_NAME="
set "MODEL_RUN_NAME="
set "MODELS_ROOT=%KIMODO_MODELS_ROOT%"
set "CPU_TEXT_ENCODER=%KIMODO_CPU_TEXT_ENCODER%"
if not defined CPU_TEXT_ENCODER set "CPU_TEXT_ENCODER=gguf"
set "GGUF_MODEL_PATH=%KIMODO_GGUF_MODEL_PATH%"
set "GGUF_CTX=%KIMODO_GGUF_CTX%"
set "USE_CPU_GGUF=0"
set "DOWNLOAD_GGUF=0"
set "VENV_PATH_ARG="
set "VENV_PY="
set "USING_EXTERNAL_MODELS=0"
set "USING_EXTERNAL_VENV=0"
set "RUN_DEVICE="
set "TEXT_ENCODER_DEVICE_MODE=%TEXT_ENCODER_DEVICE%"
set "CONFIG_ONLY=%KIMODO_CONFIG_ONLY%"
if not defined CONFIG_ONLY set "CONFIG_ONLY=0"
set "WATCHDOG_INTERVAL_SEC=%KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC%"
if not defined WATCHDOG_INTERVAL_SEC set "WATCHDOG_INTERVAL_SEC=1"
set "WATCHDOG_MAX_FAILS=%KIMODO_WATCHDOG_STARTUP_MAX_FAILS%"
if not defined WATCHDOG_MAX_FAILS set "WATCHDOG_MAX_FAILS=180"
set "WATCHDOG_RUNTIME_INTERVAL_SEC=%KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC%"
if not defined WATCHDOG_RUNTIME_INTERVAL_SEC set "WATCHDOG_RUNTIME_INTERVAL_SEC=1"
set "WATCHDOG_IDLE_NOLOG_MAX=%KIMODO_WATCHDOG_IDLE_NOLOG_MAX%"
if not defined WATCHDOG_IDLE_NOLOG_MAX set "WATCHDOG_IDLE_NOLOG_MAX=300"
set "SERVER_WINDOW_STYLE=%KIMODO_SERVER_WINDOW_STYLE%"
if not defined SERVER_WINDOW_STYLE set "SERVER_WINDOW_STYLE=Normal"
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
if /I "%~1"=="--device" (
  set "RUN_DEVICE=%~2"
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
if exist "%SETUP_LOCK%" (
  echo [WARN] Found stale setup lock, archiving: %SETUP_LOCK%
  call "%COMMON_ENV_BAT%" :archive_file "%SETUP_LOCK%" "%RECYCLE_DIR%"
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
if defined RUN_DEVICE (
  if /I "%RUN_DEVICE%"=="cpu" (
    set "TEXT_ENCODER_DEVICE_MODE=cpu"
  ) else (
    if /I "%RUN_DEVICE%"=="cuda" (
      set "RUN_DEVICE=cuda:0"
      if not defined TEXT_ENCODER_DEVICE_MODE set "TEXT_ENCODER_DEVICE_MODE=auto"
    ) else (
      if /I "%RUN_DEVICE:~0,4%"=="cuda" (
        if not defined TEXT_ENCODER_DEVICE_MODE set "TEXT_ENCODER_DEVICE_MODE=auto"
      ) else (
        echo [ERROR] Invalid --device value: %RUN_DEVICE%
        echo [ERROR] Allowed values: cpu ^| cuda ^| cuda:0 ...
        exit /b 1
      )
    )
  )
) else (
  if not defined TEXT_ENCODER_DEVICE_MODE set "TEXT_ENCODER_DEVICE_MODE=auto"
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
if not defined GGUF_MODEL_PATH set "GGUF_MODEL_PATH=%MODELS_ROOT%\Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF"
if exist "%PORT_FILE%" (
  echo [WARN] Found existing serverport, archiving stale file before fresh launch.
  call "%COMMON_ENV_BAT%" :archive_file "%PORT_FILE%" "%RECYCLE_DIR%"
)

set "SETUP_DEVICE_ARG="
if defined RUN_DEVICE (
  if /I "%RUN_DEVICE%"=="cpu" set "SETUP_DEVICE_ARG=cpu"
  if /I "%RUN_DEVICE:~0,4%"=="cuda" set "SETUP_DEVICE_ARG=cuda"
)
call "%RUN_SETUP_PHASE_BAT%" "%ROOT_DIR%" "%OUTPUT_MODE%" "%USING_EXTERNAL_VENV%" "%SETUP_SENTINEL%" "%SETUP_BAT%" "%LOG_DIR%\%LOG_NAME_SETUP%" "%SETUP_DEVICE_ARG%"
if errorlevel 1 exit /b 1

if defined RUN_DEVICE (
  if /I "%RUN_DEVICE%"=="cpu" (
    if /I "%CPU_TEXT_ENCODER%"=="gguf" (
      set "USE_CPU_GGUF=1"
      set "DOWNLOAD_GGUF=1"
    )
  )
)
set "KIMODO_DOWNLOAD_GGUF=%DOWNLOAD_GGUF%"
call "%RUN_DOWNLOAD_PHASE_BAT%" "%ROOT_DIR%" "%OUTPUT_MODE%" "%USING_EXTERNAL_MODELS%" "%HIGHVRAM%" "%MODEL_RUN_NAME%" "%MODEL_NAME%" "%DOWNLOAD_BAT%" "%LOG_DIR%\%LOG_NAME_DOWNLOAD%"
if errorlevel 1 exit /b 1

if not defined VENV_PY set "VENV_PY=%SOURCE_ROOT%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)
echo [STEP] Preflight runtime import check...
"%VENV_PY%" -c "import torch, kimodo, motion_correction; print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda))"
if errorlevel 1 (
  echo [ERROR] Runtime preflight failed: cannot import torch/kimodo/motion_correction.
  echo [ERROR] Please rerun setup: bash\setup.bat --force --device cpu ^| cuda
  exit /b 1
)

if not exist "%MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors" (
  echo [ERROR] Missing model file: %MODELS_ROOT%\%MODEL_DIR_NAME%\model.safetensors
  exit /b 1
)
if "%USE_CPU_GGUF%"=="1" (
  if not exist "%GGUF_MODEL_PATH%" (
    echo [ERROR] CPU gguf mode enabled but path missing: %GGUF_MODEL_PATH%
    exit /b 1
  )
  set "GGUF_MODEL_FILE="
  if /I "%GGUF_MODEL_PATH:~-5%"==".gguf" (
    set "GGUF_MODEL_FILE=%GGUF_MODEL_PATH%"
  ) else (
    for /f "delims=" %%F in ('dir /b /s "%GGUF_MODEL_PATH%\*.gguf" 2^>nul') do (
      if not defined GGUF_MODEL_FILE set "GGUF_MODEL_FILE=%%F"
    )
  )
  if not defined GGUF_MODEL_FILE (
    echo [ERROR] CPU gguf mode enabled but no .gguf found under: %GGUF_MODEL_PATH%
    exit /b 1
  )
  set "KIMODO_GGUF_MODEL_PATH=!GGUF_MODEL_FILE!"
) else if "%HIGHVRAM%"=="1" (
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

set "PYTHONPATH=%SOURCE_ROOT%"
set "KIMODO_ROOT_PATH=%ROOT_DIR%"
set "CHECKPOINT_DIR=%MODELS_ROOT%"
set "LOCAL_CACHE=true"
if "%USE_CPU_GGUF%"=="1" (
  set "TEXT_ENCODER_MODE=api"
  set "TEXT_ENCODER_API_BACKEND=llama"
  set "KIMODO_CPU_TEXT_ENCODER=gguf"
  if defined GGUF_CTX set "KIMODO_GGUF_CTX=%GGUF_CTX%"
  set "TEXT_ENCODER_DEVICE=cpu"
) else (
  set "TEXT_ENCODER_MODE=local"
  set "TEXT_ENCODER=llm2vec"
  set "TEXT_ENCODER_DEVICE=%TEXT_ENCODER_DEVICE_MODE%"
)
echo [INFO] Runtime device: %RUN_DEVICE%
echo [INFO] Text encoder device: %TEXT_ENCODER_DEVICE%
if "%USE_CPU_GGUF%"=="1" (
  echo [INFO] CPU text encoder mode: gguf
  echo [INFO] GGUF model path: !KIMODO_GGUF_MODEL_PATH!
)
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

set "KIMODO_IDLE_TIMEOUT_SEC=600"
if exist "%BRIDGE_PID_FILE%" call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_PID_FILE%" "%RECYCLE_DIR%"

if /I "%OUTPUT_MODE%"=="file" (
  echo [INFO] run_server log: %LOG_PATH%
  echo [INFO] bridge server log: %BOOTSTRAP_LOG_PATH%
  echo [INFO] bridge message log: %BRIDGE_MESSAGE_LOG_PATH%
  type nul > "%LOG_PATH%"
  if exist "%BOOTSTRAP_LOG_PATH%" call "%COMMON_ENV_BAT%" :archive_file "%BOOTSTRAP_LOG_PATH%" "%RECYCLE_DIR%"
  type nul > "%BOOTSTRAP_LOG_PATH%"
  if exist "%BRIDGE_MESSAGE_LOG_PATH%" call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_MESSAGE_LOG_PATH%" "%RECYCLE_DIR%"
  type nul > "%BRIDGE_MESSAGE_LOG_PATH%"
)

if defined RUN_DEVICE (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_BRIDGE_PS1%" ^
    -PythonPath "%VENV_PY%" ^
    -RootDir "%ROOT_DIR%" ^
    -ModelName "%MODEL_RUN_NAME%" ^
    -Device "%RUN_DEVICE%" ^
    -WindowStyle "%SERVER_WINDOW_STYLE%" ^
    -BridgeLogPath "%BOOTSTRAP_LOG_PATH%" ^
    -BridgeMessageLogPath "%BRIDGE_MESSAGE_LOG_PATH%" ^
    -PidFile "%BRIDGE_PID_FILE%" ^
    -OutputMode "%OUTPUT_MODE%"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCH_BRIDGE_PS1%" ^
    -PythonPath "%VENV_PY%" ^
    -RootDir "%ROOT_DIR%" ^
    -ModelName "%MODEL_RUN_NAME%" ^
    -WindowStyle "%SERVER_WINDOW_STYLE%" ^
    -BridgeLogPath "%BOOTSTRAP_LOG_PATH%" ^
    -BridgeMessageLogPath "%BRIDGE_MESSAGE_LOG_PATH%" ^
    -PidFile "%BRIDGE_PID_FILE%" ^
    -OutputMode "%OUTPUT_MODE%"
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
call "%WATCHDOG_BRIDGE_BAT%" "%ROOT_DIR%" "%SERVER_PID%" "%PORT_FILE%" "%BOOTSTRAP_LOG_PATH%" "%WATCHDOG_INTERVAL_SEC%" "%WATCHDOG_MAX_FAILS%" "%WATCHDOG_RUNTIME_INTERVAL_SEC%" "%WATCHDOG_IDLE_NOLOG_MAX%"
set "RC=%ERRORLEVEL%"
call "%COMMON_ENV_BAT%" :archive_file "%BRIDGE_PID_FILE%" "%RECYCLE_DIR%"
exit /b %RC%
