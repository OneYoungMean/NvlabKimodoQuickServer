@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
set "ROOT_DIR=%SCRIPT_DIR%\.."
set "SOURCE_ROOT="
set "LOCK_FILE=%ROOT_DIR%\.setup.lock"
set "RUN_MARKER=%ROOT_DIR%\run"
set "SETUP_LOG=%ROOT_DIR%\log\setup_buildenv_impl.log"
set "RECYCLE_DIR=%ROOT_DIR%\archive\recycle"
set "RECOVERY_FLAG_DIR=%ROOT_DIR%\archive\recovery_flags"
set "LLAMA_DIR=%ROOT_DIR%\program\exe\llama"
set "LLAMA_SERVER_EXE=%LLAMA_DIR%\llama-server.exe"

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
set "UV_CONFIG_FILE=%ROOT_DIR%\uv.toml"
set "UV_CACHE_DIR=%ROOT_DIR%\archive\uv_cache"
set "UV_PYTHON_INSTALL_DIR=%ROOT_DIR%\archive\uv_python"
set "LOCAL_WHEELS_DIR=%ROOT_DIR%\wheels"
set "ANTLR4_WHEEL=%LOCAL_WHEELS_DIR%\antlr4_python3_runtime-4.9.3-py3-none-any.whl"
set "PYTHON_SPEC="
set "INJECT_ONCE=0"
set "SETUP_DEVICE=%KIMODO_TEST_SETUP_DEVICE%"
if not defined SETUP_DEVICE set "SETUP_DEVICE="
set "BITSANDBYTES_REQUIRED=0.49.2"
set "UV_DEFAULT_INDEX="

if defined KIMODO_TEST_SCENARIO_NAME echo [TEST] scenario=%KIMODO_TEST_SCENARIO_NAME%

call :ensure_uv
if errorlevel 1 (
  echo [ERROR] uv not found.
  echo [ERROR] Install uv first, then retry setup.
  echo [ERROR] Docs: https://docs.astral.sh/uv/getting-started/installation/
  exit /b 1
)
if not exist "%UV_CACHE_DIR%" mkdir "%UV_CACHE_DIR%" >nul 2>nul
set "UV_CACHE_DIR=%UV_CACHE_DIR%"
if not exist "%UV_PYTHON_INSTALL_DIR%" mkdir "%UV_PYTHON_INSTALL_DIR%" >nul 2>nul
set "UV_PYTHON_INSTALL_DIR=%UV_PYTHON_INSTALL_DIR%"
set "PATH=%ROOT_DIR%\program\exe\uv;%PATH%"
call :ensure_local_git_lfs
if errorlevel 1 (
  echo [ERROR] local git/git-lfs check failed.
  exit /b 1
)
call :ensure_llama_server
if errorlevel 1 (
  echo [ERROR] llama-server provisioning failed.
  exit /b 1
)

call :select_uv_default_index
if errorlevel 1 exit /b 1
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

echo [STEP] Installing local antlr4 runtime wheel...
if not exist "%ANTLR4_WHEEL%" (
  echo [ERROR] Missing required local wheel: %ANTLR4_WHEEL%
  exit /b 1
)
"%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --no-index --find-links "%LOCAL_WHEELS_DIR%" --only-binary antlr4-python3-runtime antlr4-python3-runtime==4.9.3
if errorlevel 1 (
  echo [ERROR] Failed to install local antlr4 runtime wheel.
  exit /b 1
)

echo [STEP] Installing kimodo package with uv pip (no git extras)...
set "KIMODO_RUNTIME_OK=0"
"%VENV_PY%" -c "import importlib.metadata as m; import tqdm, huggingface_hub, safetensors; print(m.version('kimodo'))" >nul 2>nul
if not errorlevel 1 (
  set "KIMODO_RUNTIME_OK=1"
)
if "%KIMODO_RUNTIME_OK%"=="0" (
  pushd "%SOURCE_ROOT%" >nul
  set "SKIP_MOTION_CORRECTION_IN_SETUP=1"
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --find-links "%LOCAL_WHEELS_DIR%" --only-binary antlr4-python3-runtime --editable . --no-build-isolation
  set "KIMODO_INSTALL_RC=%ERRORLEVEL%"
  set "SKIP_MOTION_CORRECTION_IN_SETUP="
  popd >nul
  "%VENV_PY%" -c "import importlib.metadata as m; import tqdm, huggingface_hub, safetensors; print(m.version('kimodo'))" >nul 2>nul
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

set "TORCH_FORCE_CPU=0"
if /I "%SETUP_DEVICE%"=="cpu" set "TORCH_FORCE_CPU=1"
if "%TORCH_FORCE_CPU%"=="1" (
  set "UV_TORCH_BACKEND=cpu"
  echo [STEP] Installing CPU torch runtime via uv...
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --torch-backend cpu --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio torch torchvision torchaudio
  if errorlevel 1 (
    echo [ERROR] CPU torch runtime install failed.
    exit /b 1
  )
  call :validate_torch_env "cpu"
  if errorlevel 1 (
    echo [ERROR] CPU torch runtime validation failed.
    exit /b 1
  )
  echo [INFO] CPU mode: skip bitsandbytes/4-bit install by policy.
) else (
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

  call "%VENV_DIR%\Scripts\activate.bat" >nul 2>nul
  echo [STEP] Installing torch runtime via torchruntime --uv...
  "%VENV_PY%" -m torchruntime install --uv torch torchvision torchaudio
  if errorlevel 1 (
    echo [ERROR] Torch runtime install failed.
    exit /b 1
  )
  call :validate_torch_env "cuda"
  if errorlevel 1 (
    echo [ERROR] CUDA torch runtime validation failed.
    exit /b 1
  )
  call :ensure_bitsandbytes "CUDA mode"
  if errorlevel 1 exit /b 1
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

:select_uv_default_index
if defined KIMODO_PIP_INDEX_URL (
  set "UV_DEFAULT_INDEX=%KIMODO_PIP_INDEX_URL%"
  set "UV_DEFAULT_INDEX=%UV_DEFAULT_INDEX:"=%"
  exit /b 0
)

set "UV_DEFAULT_INDEX=https://pypi.org/simple"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$u='https://pypi.tuna.tsinghua.edu.cn/simple';" ^
  "try { Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 2 -Uri $u | Out-Null; exit 0 } catch { exit 1 }" >nul 2>nul
if not errorlevel 1 (
  set "UV_DEFAULT_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
)
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

:ensure_local_git_lfs
set "LOCAL_GIT_CMD=%ROOT_DIR%\program\exe\git\cmd"
set "LOCAL_GIT_LFS=%ROOT_DIR%\program\exe\git\mingw32\bin"
if not exist "%LOCAL_GIT_CMD%\git.exe" (
  echo [ERROR] local git missing: %LOCAL_GIT_CMD%\git.exe
  exit /b 1
)
if not exist "%LOCAL_GIT_LFS%\git-lfs.exe" (
  echo [ERROR] local git-lfs missing: %LOCAL_GIT_LFS%\git-lfs.exe
  exit /b 1
)
set "PATH=%LOCAL_GIT_CMD%;%LOCAL_GIT_LFS%;%PATH%"
git --version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] local git is not executable.
  exit /b 1
)
git lfs version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] local git-lfs is not executable.
  exit /b 1
)
echo [OK] local git/git-lfs are ready in local context.
exit /b 0

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

:ensure_llama_server
if exist "%LLAMA_SERVER_EXE%" (
  "%LLAMA_SERVER_EXE%" --version >nul 2>nul
  if not errorlevel 1 (
    echo [OK] local llama-server ready: %LLAMA_SERVER_EXE%
    exit /b 0
  )
)
if not exist "%LLAMA_SERVER_EXE%" (
  echo [ERROR] Missing local llama-server: %LLAMA_SERVER_EXE%
  echo [ERROR] Place llama runtime files under: %LLAMA_DIR%
  exit /b 1
)
echo [ERROR] local llama-server exists but is not executable: %LLAMA_SERVER_EXE%
exit /b 1

:validate_torch_env
set "VALIDATE_MODE=%~1"
if /I "%VALIDATE_MODE%"=="cpu" (
  echo [STEP] Validating CPU torch runtime...
  "%VENV_PY%" -c "import importlib,torch,sys; importlib.import_module('torch._jit_internal'); print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); sys.exit(0)"
  if errorlevel 1 (
    echo [ERROR] Python environment is abnormal for CPU runtime.
    echo [ERROR] Please reinstall setup from the test path with CPU mode.
    exit /b 1
  )
  exit /b 0
)
echo [STEP] Validating CUDA torch runtime...
"%VENV_PY%" -c "import importlib,torch,sys; importlib.import_module('torch._jit_internal'); print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); sys.exit(0 if (torch.cuda.is_available() and torch.version.cuda is not None) else 2)"
if errorlevel 1 (
  echo [ERROR] Python environment is abnormal for CUDA runtime.
  echo [ERROR] Please reinstall setup with auto mode.
  exit /b 1
)
exit /b 0

:ensure_bitsandbytes
set "BNB_CONTEXT=%~1"
echo [STEP] Ensuring bitsandbytes for %BNB_CONTEXT%...
"%VENV_PY%" -c "import bitsandbytes as bnb; from packaging.version import Version as V; import sys; v=V(getattr(bnb,'__version__','0')); m=V('0.46.1'); sys.exit(0 if v.__ge__(m) else 1)" >nul 2>nul
if errorlevel 1 (
  "%UV_BIN%" pip install --python "%VENV_PY%" "bitsandbytes==%BITSANDBYTES_REQUIRED%"
  if errorlevel 1 (
    echo [ERROR] Failed to install bitsandbytes for %BNB_CONTEXT%.
    exit /b 1
  )
  "%VENV_PY%" -c "import bitsandbytes as bnb; from packaging.version import Version as V; import sys; v=V(getattr(bnb,'__version__','0')); m=V('0.46.1'); sys.exit(0 if v.__ge__(m) else 1)"
  if errorlevel 1 (
    echo [ERROR] bitsandbytes version check failed after install for %BNB_CONTEXT%.
    exit /b 1
  )
) else (
  echo [INFO] bitsandbytes>=0.46.1 already present, skip reinstall.
)
exit /b 0


