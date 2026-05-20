@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "SOURCE_ROOT="
set "LOCK_FILE=%ROOT_DIR%\.setup.lock"
set "RUN_MARKER=%ROOT_DIR%\run"
set "SETUP_LOG=%ROOT_DIR%\log\setup_buildenv_impl.log"
set "NETWORK_PROBE_PS1=%ROOT_DIR%\bash\probe_network_env.ps1"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "RECOVERY_FLAG_DIR=%ROOT_DIR%\archive\recovery_flags"

if not exist "%ROOT_DIR%" exit /b 1
if not exist "%ROOT_DIR%\log" mkdir "%ROOT_DIR%\log" >nul 2>nul

if exist "%ROOT_DIR%\kimodo\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%\kimodo"
if not defined SOURCE_ROOT if exist "%ROOT_DIR%\pyproject.toml" set "SOURCE_ROOT=%ROOT_DIR%"
if not defined SOURCE_ROOT (
  echo [ERROR] Invalid project root: %ROOT_DIR%
  exit /b 1
)

if not exist "%SOURCE_ROOT%\pyproject.toml" (
  echo [ERROR] Missing pyproject.toml under: %SOURCE_ROOT%
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

set "SETUP_EXIT=0"
if errorlevel 1 set "SETUP_EXIT=1"
if "%SETUP_EXIT%"=="0" if not exist "%RUN_MARKER%" mkdir "%RUN_MARKER%"
call :archive_file "%LOCK_FILE%"
exit /b %SETUP_EXIT%

:run_setup
set "UV_BIN=%ROOT_DIR%\program\exe\uv\uv.exe"
set "UV_DEFAULT_INDEX=https://pypi.org/simple"
set "UV_INDEX_CANDIDATE_CN=https://mirrors.aliyun.com/pypi/simple/"
set "UV_INDEX_CANDIDATE_GLOBAL=https://pypi.org/simple"
set "NETWORK_ENV_CMD=%TEMP%\kimodo_probe_env_%RANDOM%%RANDOM%.cmd"
set "PYTHON_SPEC="
set "INJECT_ONCE=0"

if defined KIMODO_TEST_SCENARIO_NAME echo [TEST] scenario=%KIMODO_TEST_SCENARIO_NAME%

call :ensure_uv
if errorlevel 1 (
  echo [ERROR] uv not found.
  echo [ERROR] Install uv first, then retry setup.
  echo [ERROR] Docs: https://docs.astral.sh/uv/getting-started/installation/
  exit /b 1
)

echo [STEP] Checking network reachability for package index...
echo [INFO] Network probe started...
if exist "%NETWORK_PROBE_PS1%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%NETWORK_PROBE_PS1%" -TimeoutSec 8 -EmitCmdFile "%NETWORK_ENV_CMD%" -Quiet
  if not errorlevel 1 (
    if exist "%NETWORK_ENV_CMD%" (
      call "%NETWORK_ENV_CMD%"
      call :archive_file "%NETWORK_ENV_CMD%"
    )
    if defined KIMODO_PIP_INDEX_URL set "UV_DEFAULT_INDEX=!KIMODO_PIP_INDEX_URL!"
  )
)
if defined KIMODO_PIP_BEST_NAME (
  if defined KIMODO_PIP_BEST_MS (
    echo [INFO] Network probe result: pip best=!KIMODO_PIP_BEST_NAME! ^(!KIMODO_PIP_BEST_MS! ms^)
  ) else (
    echo [INFO] Network probe result: pip best=!KIMODO_PIP_BEST_NAME!
  )
)
if defined KIMODO_PY_ZIP_BEST_NAME (
  if defined KIMODO_PY_ZIP_BEST_MS (
    echo [INFO] Network probe result: python zip best=!KIMODO_PY_ZIP_BEST_NAME! ^(!KIMODO_PY_ZIP_BEST_MS! ms^)
  ) else (
    echo [INFO] Network probe result: python zip best=!KIMODO_PY_ZIP_BEST_NAME!
  )
)
if defined UV_DEFAULT_INDEX set "UV_DEFAULT_INDEX=!UV_DEFAULT_INDEX:"=!"
if not defined UV_DEFAULT_INDEX set "UV_DEFAULT_INDEX=%UV_INDEX_CANDIDATE_GLOBAL%"

if /I "%UV_DEFAULT_INDEX%"=="https://pypi.org/simple" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop'; $u='%UV_INDEX_CANDIDATE_CN%'; $t=20;" ^
    "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec $t -Uri $u | Out-Null; exit 0 } catch { exit 1 }"
  if not errorlevel 1 set "UV_DEFAULT_INDEX=%UV_INDEX_CANDIDATE_CN%"
)

call :should_inject_once "setup_net_bad" "KIMODO_TEST_INJECT_SETUP_NET_BAD_ONCE"
if "!INJECT_ONCE!"=="1" (
  set "UV_DEFAULT_INDEX=http://127.0.0.1:9/simple"
  echo [TEST] Injected setup network failure once: UV_DEFAULT_INDEX=%UV_DEFAULT_INDEX%
)

echo [INFO] Selected uv default index: %UV_DEFAULT_INDEX%

call :select_python_spec
if errorlevel 1 exit /b 1

echo [STEP] Ensuring uv-managed Python: %PYTHON_SPEC%
"%UV_BIN%" python install "%PYTHON_SPEC%"
if errorlevel 1 (
  echo [ERROR] Failed to install or locate Python via uv: %PYTHON_SPEC%
  exit /b 1
)

set "VENV_DIR=%SOURCE_ROOT%\.venv"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
echo [STEP] Creating/updating venv with uv...
"%UV_BIN%" venv "%VENV_DIR%" --python "%PYTHON_SPEC%" --allow-existing
if errorlevel 1 (
  echo [ERROR] uv venv failed.
  exit /b 1
)
if not exist "%VENV_PY%" (
  echo [ERROR] venv python missing: %VENV_PY%
  exit /b 1
)

call :should_inject_once "setup_abort" "KIMODO_TEST_INJECT_SETUP_ABORT_ONCE"
if "!INJECT_ONCE!"=="1" (
  echo [TEST] Injected setup interrupt once after venv creation.
  exit /b 91
)

echo [STEP] Seeding build helpers in venv...
"%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" pip setuptools wheel
if errorlevel 1 (
  echo [ERROR] Failed to install build helpers pip/setuptools/wheel.
  exit /b 1
)

echo [STEP] Installing kimodo package with uv pip (no git extras)...
"%VENV_PY%" -c "import importlib.metadata as m; print(m.version('kimodo'))" >nul 2>nul
if errorlevel 1 (
  pushd "%SOURCE_ROOT%" >nul
  set "SKIP_MOTION_CORRECTION_IN_SETUP=1"
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --editable . --no-build-isolation
  set "KIMODO_INSTALL_RC=%ERRORLEVEL%"
  set "SKIP_MOTION_CORRECTION_IN_SETUP="
  popd >nul
  "%VENV_PY%" -c "import importlib.metadata as m; print(m.version('kimodo'))" >nul 2>nul
  if errorlevel 1 (
    echo [ERROR] Failed to install kimodo package via uv pip.
    exit /b 1
  )
  if not "!KIMODO_INSTALL_RC!"=="0" (
    echo [WARN] uv pip returned non-zero, but kimodo import check passed.
  )
) else (
  echo [INFO] kimodo already usable, skip reinstall.
)

echo [STEP] Ensuring torchruntime helper...
"%VENV_PY%" -c "import torchruntime" >nul 2>nul
if errorlevel 1 (
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" torchruntime
  if errorlevel 1 (
    echo [ERROR] Failed to install torchruntime.
    exit /b 1
  )
) else (
  echo [INFO] torchruntime already present, skip reinstall.
)

echo [STEP] Ensuring PyTorch runtime...
"%VENV_PY%" -c "import torch, torchvision, torchaudio; print(torch.__version__)" >nul 2>nul
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

echo [STEP] Ensuring bitsandbytes for 4-bit quantization...
"%VENV_PY%" -c "import bitsandbytes as bnb; print(getattr(bnb, '__version__', 'unknown'))" >nul 2>nul
if errorlevel 1 (
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" "bitsandbytes>=0.46.1"
  if errorlevel 1 (
    echo [ERROR] Failed to install bitsandbytes.
    exit /b 1
  )
) else (
  echo [INFO] bitsandbytes already present, skip reinstall.
)

echo [STEP] Ensuring motion_correction...
set "MC_WHL_WIN=%ROOT_DIR%\wheels\motion_correction-1.0.0-cp312-cp312-win_amd64.whl"
set "MC_WHL_LINUX=%ROOT_DIR%\wheels\motion_correction-1.0.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
"%VENV_PY%" -c "import motion_correction" >nul 2>nul
if errorlevel 1 (
  if exist "%MC_WHL_WIN%" (
    "%UV_BIN%" pip install --python "%VENV_PY%" "%MC_WHL_WIN%"
    if errorlevel 1 (
      echo [ERROR] Failed to install motion_correction wheel: %MC_WHL_WIN%
      exit /b 1
    )
  ) else if exist "%MC_WHL_LINUX%" (
    "%UV_BIN%" pip install --python "%VENV_PY%" "%MC_WHL_LINUX%"
    if errorlevel 1 (
      echo [ERROR] Failed to install motion_correction wheel: %MC_WHL_LINUX%
      exit /b 1
    )
  ) else (
    echo [ERROR] Missing motion_correction wheel under: %ROOT_DIR%\wheels
    exit /b 1
  )
) else (
  echo [INFO] motion_correction already present, skip reinstall.
)

if not exist "%ROOT_DIR%\models" mkdir "%ROOT_DIR%\models"

set "PYTHONPATH=%SOURCE_ROOT%"
"%VENV_PY%" -c "import numpy, huggingface_hub, safetensors; import kimodo.model.load_model"
if errorlevel 1 (
  echo [ERROR] Runtime check failed: cannot import runtime deps in venv.
  exit /b 1
)

if defined KIMODO_BUILDENV_ONLY (
  echo [OK] Build environment staged.
  echo [INFO] ROOT_DIR=%ROOT_DIR%
  echo [INFO] SOURCE_ROOT=%SOURCE_ROOT%
  echo [INFO] VENV_PY=%VENV_PY%
  exit /b 0
)

echo [OK] Build environment staged.
echo [INFO] ROOT_DIR=%ROOT_DIR%
echo [INFO] SOURCE_ROOT=%SOURCE_ROOT%
echo [INFO] VENV_PY=%VENV_PY%
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

:ensure_uv
if exist "%UV_BIN%" (
  "%UV_BIN%" --version >nul 2>nul
  if not errorlevel 1 (
    echo [INFO] Using local uv: %UV_BIN%
    exit /b 0
  )
)
echo [ERROR] Local uv missing or unusable: %UV_BIN%
echo [ERROR] Please place uv.exe under program\exe\uv before running setup.
exit /b 1

:select_python_spec
set "PYTHON_SPEC=3.12"
if /I not "%OS%"=="Windows_NT" exit /b 0
if /I "%KIMODO_PYTHON_ARCH%"=="x86" (
  echo [ERROR] x86 Python is not supported for this pipeline.
  echo [ERROR] Reason: torch wheels are unavailable on win32 for required versions.
  echo [ERROR] Use default x64 Python or set KIMODO_PYTHON_ARCH=x64.
  exit /b 1
)
set "PYTHON_SPEC=cpython-3.12.13-windows-x86_64-none"
echo [INFO] Python arch selected: x64 ^(required by torch wheels on Windows^).
exit /b 0
