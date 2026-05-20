@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%"
set "MODEL_NAME=Kimodo-SOMA-RP-v1"
set "HIGHVRAM=0"
set "OUTPUT_MODE=console"
set "LOG_PATH=%ROOT_DIR%\run_server.log"
set "SETUP_BAT=%ROOT_DIR%\setup.bat"
set "DOWNLOAD_BAT=%ROOT_DIR%\download_model.bat"
set "SETUP_LOCK=%ROOT_DIR%\.setup_new.lock"
set "SETUP_SENTINEL=%ROOT_DIR%\.setup_new_complete"
set "PORT_FILE=%ROOT_DIR%\serverport"
set "SERVER_STATE=%ROOT_DIR%\.run_server_state"
set "SOURCE_ROOT="
set "MODEL_DIR_NAME="
set "MODEL_RUN_NAME="

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
if /I "%~1"=="--force-setup" (
  if exist "%SETUP_SENTINEL%" del /q "%SETUP_SENTINEL%" >nul 2>nul
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

call :resolve_model_alias "%MODEL_NAME%"
if errorlevel 1 exit /b 1

if exist "%SETUP_LOCK%" (
  echo [ERROR] setup is running: %SETUP_LOCK%
  exit /b 1
)

if /I "%HIGHVRAM%"=="1" (
  set "KIMODO_LLM2VEC_DIR=%ROOT_DIR%\models\Meta-Llama-3-8B-Instruct"
  set "TEXT_ENCODERS_DIR=%ROOT_DIR%\models"
  set "KIMODO_LLM2VEC_PEFT_DIR=%ROOT_DIR%\models\LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
) else (
  set "KIMODO_LLM2VEC_DIR=%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4"
  set "TEXT_ENCODERS_DIR="
  set "KIMODO_LLM2VEC_PEFT_DIR="
)

set "CUR_SIG=model=%MODEL_RUN_NAME%;highvram=%HIGHVRAM%;llm2vec=%KIMODO_LLM2VEC_DIR%"
set "PREV_SIG="
if exist "%SERVER_STATE%" (
  for /f "usebackq tokens=1,* delims==" %%A in ("%SERVER_STATE%") do (
    if /I "%%A"=="sig" set "PREV_SIG=%%B"
  )
)

if exist "%PORT_FILE%" (
  if /I not "%PREV_SIG%"=="%CUR_SIG%" (
    echo [STEP] Existing server params differ, stopping previous server...
    call :shutdown_existing
    if errorlevel 1 exit /b 1
  ) else (
    echo [INFO] Existing server already running with same params: %CUR_SIG%
    exit /b 0
  )
)

if not exist "%SETUP_SENTINEL%" (
  echo [STEP] setup not found, running setup...
  call "%SETUP_BAT%" --output %OUTPUT_MODE% --log "%ROOT_DIR%\setup.log"
  if errorlevel 1 exit /b 1
)

echo [STEP] Downloading model assets for model=%MODEL_NAME% highvram=%HIGHVRAM%...
if "%HIGHVRAM%"=="1" (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%ROOT_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%" --highvram
) else (
  call "%DOWNLOAD_BAT%" --output "%OUTPUT_MODE%" --log "%ROOT_DIR%\download_model.log" --unlock-stale --model "%MODEL_RUN_NAME%"
)
if errorlevel 1 exit /b 1

set "VENV_PY=%ROOT_DIR%\.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
  echo [ERROR] Missing venv python: %VENV_PY%
  exit /b 1
)

if not exist "%ROOT_DIR%\models\%MODEL_DIR_NAME%\model.safetensors" (
  echo [ERROR] Missing model file: %ROOT_DIR%\models\%MODEL_DIR_NAME%\model.safetensors
  exit /b 1
)
if not exist "%KIMODO_LLM2VEC_DIR%\model.safetensors" (
  echo [ERROR] Missing text encoder model: %KIMODO_LLM2VEC_DIR%\model.safetensors
  exit /b 1
)
if "%HIGHVRAM%"=="1" (
  if not exist "%ROOT_DIR%\models\Meta-Llama-3-8B-Instruct\model.safetensors.index.json" if not exist "%ROOT_DIR%\models\Meta-Llama-3-8B-Instruct\model.safetensors" (
    echo [ERROR] Missing Meta-Llama model under %ROOT_DIR%\models\Meta-Llama-3-8B-Instruct
    exit /b 1
  )
  if not exist "%KIMODO_LLM2VEC_PEFT_DIR%\adapter_model.safetensors" if not exist "%KIMODO_LLM2VEC_PEFT_DIR%\model.safetensors" (
    echo [ERROR] Missing LLM2Vec PEFT model under %KIMODO_LLM2VEC_PEFT_DIR%
    exit /b 1
  )
)

set "PYTHONPATH=%SOURCE_ROOT%"
set "KIMODO_ROOT_PATH=%ROOT_DIR%"
set "CHECKPOINT_DIR=%ROOT_DIR%\models"
set "LOCAL_CACHE=true"
set "TEXT_ENCODER_MODE=local"
set "TEXT_ENCODER=llm2vec"
set "HF_HOME=%ROOT_DIR%\hf_cache"
set "TRANSFORMERS_CACHE=%HF_HOME%\transformers"
set "HUGGINGFACE_HUB_CACHE=%HF_HOME%\hub"
set "HF_HUB_CACHE=%HF_HOME%\hub"
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

if /I "%OUTPUT_MODE%"=="file" (
  set "LOG_USED=%LOG_PATH%"
  if exist "!LOG_USED!" set "LOG_USED=%ROOT_DIR%\\run_server_!RANDOM!!RANDOM!.log"
  echo [INFO] run_server log: !LOG_USED!
  pushd "%ROOT_DIR%" >nul
  "%VENV_PY%" -u -m kimodo.bridge.bridge_server --model "%MODEL_RUN_NAME%" --kimodo-root "%ROOT_DIR%" > "!LOG_USED!" 2>&1
  set "RC=%ERRORLEVEL%"
  popd >nul
  exit /b %RC%
)

pushd "%ROOT_DIR%" >nul
"%VENV_PY%" -u -m kimodo.bridge.bridge_server --model "%MODEL_RUN_NAME%" --kimodo-root "%ROOT_DIR%"
set "RC=%ERRORLEVEL%"
popd >nul
exit /b %RC%

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
  echo [ERROR] Timeout waiting previous server to stop.
  exit /b 1
)
goto wait_old_exit
