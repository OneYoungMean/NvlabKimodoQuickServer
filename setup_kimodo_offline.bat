@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT_DIR=%CD%"
set "SOURCE_ROOT="
set "LOCK_FILE=%ROOT_DIR%\.setup.lock"
set "RUN_MARKER=%ROOT_DIR%\run"
set "SETUP_SENTINEL=%ROOT_DIR%\.kimodo_offline_setup_complete"
set "SETUP_LOG=%ROOT_DIR%\setup_kimodo_offline.log"

if not exist "%ROOT_DIR%" exit /b 1

if exist "%ROOT_DIR%\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%"
if not defined SOURCE_ROOT if exist "%ROOT_DIR%\kimodo\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%\kimodo"
if not defined SOURCE_ROOT (
  echo [ERROR] Invalid project root: %ROOT_DIR%
  exit /b 1
)

if not exist "%SOURCE_ROOT%\kimodo\model\load_model.py" (
  echo [ERROR] Invalid source layout under: %SOURCE_ROOT%
  exit /b 1
)

> "%LOCK_FILE%" (
  echo started=%DATE% %TIME%
  echo root=%ROOT_DIR%
)

if defined KIMODO_SETUP_BG (
  call :run_setup
) else (
  echo [INFO] Setup log will be saved to: %SETUP_LOG%
  call :run_setup > "%SETUP_LOG%" 2>&1
)
set "SETUP_EXIT=%ERRORLEVEL%"
if "%SETUP_EXIT%"=="0" if not exist "%RUN_MARKER%" mkdir "%RUN_MARKER%"
del /q "%LOCK_FILE%" >nul 2>nul
exit /b %SETUP_EXIT%

:run_setup
set "PIP_INDEX_URL_CN=https://mirrors.aliyun.com/pypi/simple/"
set "PIP_TRUSTED_HOST_CN=mirrors.aliyun.com"
set "PIP_INDEX_URL_GLOBAL=https://pypi.org/simple"
set "PIP_TRUSTED_HOST_GLOBAL=pypi.org"
set "PIP_INDEX_URL="
set "PIP_TRUSTED_HOST="
set "PIP_COMMON="
set "PY_ZIP_MIRROR_BASE=https://mirrors.tuna.tsinghua.edu.cn/python/"
set "PY_ZIP_OFFICIAL_BASE=https://www.python.org/ftp/python/"

echo [STEP] Checking network reachability...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $u='%PIP_INDEX_URL_CN%'; $t=20;" ^
  "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $t -Uri $u | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 (
  set "PIP_INDEX_URL=%PIP_INDEX_URL_CN%"
  set "PIP_TRUSTED_HOST=%PIP_TRUSTED_HOST_CN%"
  echo [INFO] Selected pip index: !PIP_INDEX_URL! ^(CN mirror^)
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $u='%PIP_INDEX_URL_GLOBAL%'; $t=20;" ^
    "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $t -Uri $u | Out-Null; exit 0 } catch { exit 1 }"
  if not errorlevel 1 (
    set "PIP_INDEX_URL=%PIP_INDEX_URL_GLOBAL%"
    set "PIP_TRUSTED_HOST=%PIP_TRUSTED_HOST_GLOBAL%"
    echo [INFO] Selected pip index: !PIP_INDEX_URL! ^(global fallback^)
  ) else (
    echo [ERROR] No reachable pip index.
    echo [ERROR] Checked:
    echo [ERROR]   %PIP_INDEX_URL_CN%
    echo [ERROR]   %PIP_INDEX_URL_GLOBAL%
    exit /b 1
  )
)
set "PIP_COMMON=--disable-pip-version-check --progress-bar off --retries 1 --timeout 60 --index-url %PIP_INDEX_URL% --trusted-host %PIP_TRUSTED_HOST%"
set "PY_MIRROR_OK=0"
set "PY_OFFICIAL_OK=0"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $u='%PY_ZIP_MIRROR_BASE%'; $t=20;" ^
  "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $t -Uri $u | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 set "PY_MIRROR_OK=1"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop'; $u='%PY_ZIP_OFFICIAL_BASE%'; $t=20;" ^
  "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $t -Uri $u | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 set "PY_OFFICIAL_OK=1"
if "%PY_MIRROR_OK%"=="0" if "%PY_OFFICIAL_OK%"=="0" (
  echo [ERROR] Python download sources not reachable.
  echo [ERROR] Checked:
  echo [ERROR]   %PY_ZIP_MIRROR_BASE%
  echo [ERROR]   %PY_ZIP_OFFICIAL_BASE%
  exit /b 1
)

set "PY_VER=3.12.10"
set "PY_ARCH=amd64"
if /I "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "PY_ARCH=arm64"

set "PY312_DIR=%ROOT_DIR%\python312"
set "PY312_EXE=%PY312_DIR%\python.exe"
set "PY_EMBED_ZIP=python-%PY_VER%-embed-%PY_ARCH%.zip"
set "PY_ZIP_MIRROR=%PY_ZIP_MIRROR_BASE%%PY_VER%/%PY_EMBED_ZIP%"
set "PY_ZIP_OFFICIAL=%PY_ZIP_OFFICIAL_BASE%%PY_VER%/%PY_EMBED_ZIP%"
set "PY_ZIP_PATH=%TEMP%\%PY_EMBED_ZIP%"
set "PIP_BOOTSTRAP_DIR=%ROOT_DIR%\pip_bootstrap"
set "GETPIP_LOCAL="

if exist "%ROOT_DIR%\get-pip\get-pip-main\public\get-pip.py" set "GETPIP_LOCAL=%ROOT_DIR%\get-pip\get-pip-main\public\get-pip.py"
if not defined GETPIP_LOCAL if exist "%PIP_BOOTSTRAP_DIR%\get-pip.py" set "GETPIP_LOCAL=%PIP_BOOTSTRAP_DIR%\get-pip.py"
if not defined GETPIP_LOCAL (
  echo [ERROR] Local get-pip.py not found.
  echo [ERROR] Expected one of:
  echo [ERROR]   %ROOT_DIR%\get-pip\get-pip-main\public\get-pip.py
  echo [ERROR]   %PIP_BOOTSTRAP_DIR%\get-pip.py
  exit /b 1
)

if not exist "%PY312_EXE%" (
  echo [STEP] Downloading embeddable Python %PY_VER% arch=%PY_ARCH%...
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri '%PY_ZIP_MIRROR%' -OutFile '%PY_ZIP_PATH%'"
  if errorlevel 1 powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -TimeoutSec 180 -Uri '%PY_ZIP_OFFICIAL%' -OutFile '%PY_ZIP_PATH%'"
  if errorlevel 1 (
    echo [ERROR] Failed to download embeddable Python zip.
    exit /b 1
  )

  if exist "%PY312_DIR%" rmdir /s /q "%PY312_DIR%"
  mkdir "%PY312_DIR%" || exit /b 1
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%PY_ZIP_PATH%' -DestinationPath '%PY312_DIR%' -Force"
  if errorlevel 1 (
    echo [ERROR] Failed to extract embeddable Python zip.
    exit /b 1
  )
)

if not exist "%PY312_EXE%" (
  echo [ERROR] Installed python not found: %PY312_EXE%
  exit /b 1
)

set "PTH_FILE=%PY312_DIR%\python312._pth"
if exist "%PTH_FILE%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$p='%PTH_FILE%'; $c=Get-Content -LiteralPath $p -Raw; $c=$c -replace '(?m)^\s*#\s*import site\s*$','import site'; if($c -notmatch '(?m)^\s*import site\s*$'){ $c += \"`r`nimport site`r`n\" }; Set-Content -LiteralPath $p -Value $c -Encoding ASCII"
)

echo [STEP] Ensuring pip...
"%PY312_EXE%" -m pip --version >nul 2>nul
if errorlevel 1 (
  if exist "%PIP_BOOTSTRAP_DIR%\pip-26.1.1-py3-none-any.whl" (
    "%PY312_EXE%" "%GETPIP_LOCAL%" --no-index --find-links "%PIP_BOOTSTRAP_DIR%"
  ) else (
    "%PY312_EXE%" "%GETPIP_LOCAL%" --index-url "%PIP_INDEX_URL%" --trusted-host "%PIP_TRUSTED_HOST%"
  )
  if errorlevel 1 (
    echo [ERROR] Failed to install pip.
    exit /b 1
  )
) else (
  echo [INFO] pip already present in python312, skip bootstrap.
)

echo [STEP] Ensuring virtualenv...
if exist "%PIP_BOOTSTRAP_DIR%\virtualenv-21.3.3-py3-none-any.whl" (
  "%PY312_EXE%" -m pip install --disable-pip-version-check --progress-bar off --retries 1 --timeout 60 --no-index --find-links "%PIP_BOOTSTRAP_DIR%" virtualenv
) else (
  "%PY312_EXE%" -m pip install %PIP_COMMON% virtualenv
)
if errorlevel 1 (
  echo [ERROR] Failed to install virtualenv.
  exit /b 1
)

set "VENV_DIR=%ROOT_DIR%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
if not exist "%VENV_PY%" "%PY312_EXE%" -m venv "%VENV_DIR%" >nul 2>nul
if not exist "%VENV_PY%" "%PY312_EXE%" -m virtualenv "%VENV_DIR%"
if not exist "%VENV_PY%" (
  echo [ERROR] venv python missing: %VENV_PY%
  exit /b 1
)

echo [STEP] Ensuring pip tools in venv...
"%VENV_PY%" -m pip install %PIP_COMMON% --upgrade pip "setuptools<82" wheel
if errorlevel 1 (
  echo [ERROR] Failed to bootstrap pip/setuptools/wheel in venv.
  exit /b 1
)

echo [STEP] Ensuring torchruntime helper...
"%VENV_PY%" -c "import torchruntime" >nul 2>nul
if errorlevel 1 (
  "%VENV_PY%" -m pip install %PIP_COMMON% torchruntime
  if errorlevel 1 (
    echo [ERROR] Failed to install torchruntime.
    exit /b 1
  )
) else (
  echo [INFO] torchruntime already present, skip reinstall.
)

echo [STEP] Ensuring PyTorch...
"%VENV_PY%" -c "import torch; import torchvision; import torchaudio; print(torch.__version__)" >nul 2>nul
if errorlevel 1 (
  "%VENV_PY%" -m torchruntime info
  "%VENV_PY%" -m torchruntime install
  if errorlevel 1 (
    echo [ERROR] torchruntime install failed.
    exit /b 1
  )
) else (
  echo [INFO] torch/torchvision/torchaudio already present, skip reinstall.
)

"%VENV_PY%" -c "import torch; print(torch.__version__); print(torch.cuda.is_available())"
if errorlevel 1 (
  echo [ERROR] Torch import check failed after torchruntime install.
  exit /b 1
)

echo [STEP] Ensuring runtime deps from pip...
"%VENV_PY%" -c "import huggingface_hub, safetensors" >nul 2>nul
if errorlevel 1 (
  "%VENV_PY%" -m pip install %PIP_COMMON% huggingface_hub safetensors
  if errorlevel 1 (
    echo [ERROR] Failed to install runtime dependencies from pip.
    exit /b 1
  )
) else (
  echo [INFO] Runtime deps already present, skip reinstall.
)

echo [STEP] Ensuring kimodo editable package...
"%VENV_PY%" -c "from kimodo import load_model" >nul 2>nul
if errorlevel 1 (
  set "SKIP_MOTION_CORRECTION_IN_SETUP=1"
  pushd "%SOURCE_ROOT%" >nul
  "%VENV_PY%" -m pip install %PIP_COMMON% -e . --no-build-isolation
  set "PKG_INSTALL_CODE=!ERRORLEVEL!"
  popd >nul
  if not "!PKG_INSTALL_CODE!"=="0" (
    echo [ERROR] Failed to install kimodo editable package from: %SOURCE_ROOT%
    exit /b 1
  )
) else (
  echo [INFO] kimodo already usable, skip reinstall.
)

echo [STEP] Ensuring bitsandbytes for 4-bit quantization...
"%VENV_PY%" -c "import bitsandbytes as bnb; print(getattr(bnb, '__version__', 'unknown'))" >nul 2>nul
if errorlevel 1 (
  "%VENV_PY%" -m pip install %PIP_COMMON% "bitsandbytes>=0.46.1"
  if errorlevel 1 (
    echo [ERROR] Failed to install bitsandbytes required for 4-bit quantization.
    exit /b 1
  )
) else (
  echo [INFO] bitsandbytes already present, skip reinstall.
)

echo [STEP] Ensuring motion_correction...
set "MC_WHL_WIN=%ROOT_DIR%\wheels\motion_correction-1.0.0-cp312-cp312-win_amd64.whl"
set "MC_WHL_LINUX=%ROOT_DIR%\wheels\motion_correction-1.0.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
set "MC_SRC=%SOURCE_ROOT%\MotionCorrection\python\motion_correction"
"%VENV_PY%" -c "import motion_correction" >nul 2>nul
if errorlevel 1 (
  if exist "%MC_WHL_WIN%" (
    "%VENV_PY%" -m pip install %PIP_COMMON% "%MC_WHL_WIN%"
  ) else if exist "%MC_WHL_LINUX%" (
    "%VENV_PY%" -m pip install %PIP_COMMON% "%MC_WHL_LINUX%"
  ) else if exist "%MC_SRC%\setup.py" (
    pushd "%MC_SRC%" >nul
    "%VENV_PY%" -m pip install -e . --no-build-isolation
    set "MC_INSTALL_CODE=!ERRORLEVEL!"
    popd >nul
    if not "!MC_INSTALL_CODE!"=="0" (
      echo [ERROR] Failed to install motion_correction from source: %MC_SRC%
      exit /b 1
    )
  ) else (
    echo [ERROR] Missing motion_correction package source and wheels.
    echo [ERROR] Expected one of:
    echo [ERROR]   %MC_WHL_WIN%
    echo [ERROR]   %MC_WHL_LINUX%
    echo [ERROR]   %MC_SRC%\setup.py
    exit /b 1
  )
  if errorlevel 1 (
    echo [ERROR] Failed to install motion_correction.
    exit /b 1
  )
) else (
  echo [INFO] motion_correction already present, skip reinstall.
)

if not exist "%ROOT_DIR%\models" mkdir "%ROOT_DIR%\models"
if not exist "%ROOT_DIR%\checkpoints" mkdir "%ROOT_DIR%\checkpoints"

set "REQ_CHECKPOINT=%ROOT_DIR%\checkpoints\Kimodo-SOMA-RP-v1\model.safetensors"
set "REQ_META_DIR=%ROOT_DIR%\models\Meta-Llama-3-8B-Instruct"
set "REQ_NF4=%ROOT_DIR%\models\KIMODO-Meta3_llm2vec_NF4\model.safetensors"

if not exist "%REQ_CHECKPOINT%" (
  echo [ERROR] Missing checkpoint required by offline bridge: %REQ_CHECKPOINT%
  exit /b 1
)
if not exist "%REQ_META_DIR%\model.safetensors.index.json" if not exist "%REQ_META_DIR%\model.safetensors" if not exist "%REQ_NF4%" (
  echo [ERROR] Missing text encoder model required by offline bridge.
  echo [ERROR] Need one of:
  echo [ERROR]   %REQ_META_DIR%
  echo [ERROR]   %REQ_NF4%
  exit /b 1
)

set "WRAPPER=%SOURCE_ROOT%\kimodo\model\llm2vec\llm2vec_wrapper.py"
if not exist "%WRAPPER%" (
  echo [ERROR] Missing wrapper file: %WRAPPER%
  exit /b 1
)

pushd "%ROOT_DIR%" >nul
set "PYTHONPATH=%SOURCE_ROOT%"
"%VENV_PY%" -c "import numpy; from kimodo import load_model; print('runtime_ok')" >nul 2>nul
set "RUNTIME_OK=%ERRORLEVEL%"
popd >nul
if not "%RUNTIME_OK%"=="0" (
  echo [ERROR] Runtime check failed: cannot import numpy/kimodo in venv.
  exit /b 1
)

> "%SETUP_SENTINEL%" (
  echo setup_time=%DATE% %TIME%
  echo venv_py=%VENV_PY%
  echo root_dir=%ROOT_DIR%
)

echo [OK] Offline setup staged.
echo [INFO] ROOT_DIR=%ROOT_DIR%
echo [INFO] VENV_PY=%VENV_PY%
echo [INFO] SENTINEL=%SETUP_SENTINEL%
exit /b 0