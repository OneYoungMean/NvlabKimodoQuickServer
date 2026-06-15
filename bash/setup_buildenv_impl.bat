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
rem Do NOT override UV_CACHE_DIR / UV_PYTHON_INSTALL_DIR: uv's default global cache
rem (under %LOCALAPPDATA%\uv) is shared across all copy_to_test DEST runs, so the
rem ~2.6GiB cu128 torch wheel and Python download only once and are reused. The
rem previous %ROOT_DIR%-based override made every DEST re-download and keep its own
rem ~5GB copy. Override KIMODO_UV_CACHE_DIR only if you must relocate the cache.
if defined KIMODO_UV_CACHE_DIR set "UV_CACHE_DIR=%KIMODO_UV_CACHE_DIR%"
if defined KIMODO_UV_PYTHON_DIR set "UV_PYTHON_INSTALL_DIR=%KIMODO_UV_PYTHON_DIR%"
rem Parallelize downloads so torch + its many deps fetch concurrently instead of
rem serially. Override KIMODO_UV_CONCURRENT_DOWNLOADS to tune; default 16.
set "UV_CONCURRENT_DOWNLOADS=%KIMODO_UV_CONCURRENT_DOWNLOADS%"
if not defined UV_CONCURRENT_DOWNLOADS set "UV_CONCURRENT_DOWNLOADS=16"
rem cu128 torch source. The Aliyun mirror hosts the cu128 wheels as a flat file
rem listing (used via --find-links) and benchmarks ~2x faster from CN networks
rem than the official index. If it is unreachable or lacks the pinned version we
rem fall back to --torch-backend cu128 (the official download.pytorch.org index).
rem Override KIMODO_TORCH_FINDLINKS to point at a different mirror, or set it empty
rem to skip the mirror and always use the official index.
set "TORCH_FINDLINKS=%KIMODO_TORCH_FINDLINKS%"
if not defined KIMODO_TORCH_FINDLINKS set "TORCH_FINDLINKS=https://mirrors.aliyun.com/pytorch-wheels/cu128"
rem Host to ping to decide whether the mirror is "close" (i.e. we are on a CN
rem network). If average latency exceeds KIMODO_TORCH_MIRROR_MAX_PING_MS the mirror
rem is skipped entirely and torch comes from the official index -- avoids paying the
rem mirror's slower find-links resolve on networks where it would not be faster.
set "TORCH_MIRROR_PING_HOST=%KIMODO_TORCH_MIRROR_PING_HOST%"
if not defined TORCH_MIRROR_PING_HOST set "TORCH_MIRROR_PING_HOST=mirrors.aliyun.com"
set "TORCH_MIRROR_MAX_PING_MS=%KIMODO_TORCH_MIRROR_MAX_PING_MS%"
if not defined TORCH_MIRROR_MAX_PING_MS set "TORCH_MIRROR_MAX_PING_MS=50"
set "LOCAL_WHEELS_DIR=%ROOT_DIR%\wheels"
set "ANTLR4_WHEEL=%LOCAL_WHEELS_DIR%\antlr4_python3_runtime-4.9.3-py3-none-any.whl"
set "PYTHON_SPEC="
set "INJECT_ONCE=0"
set "SETUP_DEVICE=%KIMODO_SETUP_DEVICE%"
if not defined SETUP_DEVICE set "SETUP_DEVICE=%KIMODO_TEST_SETUP_DEVICE%"
if not defined SETUP_DEVICE set "SETUP_DEVICE=auto"
if /I "%SETUP_DEVICE%"=="cuda" set "SETUP_DEVICE=auto"
set "BITSANDBYTES_REQUIRED=0.49.2"
set "UV_DEFAULT_INDEX="

call :print_environment

if defined KIMODO_TEST_SCENARIO_NAME echo [TEST] scenario=%KIMODO_TEST_SCENARIO_NAME%

call :ensure_uv
if errorlevel 1 (
  echo [ERROR] uv not found.
  echo [ERROR] Install uv first, then retry setup.
  echo [ERROR] Docs: https://docs.astral.sh/uv/getting-started/installation/
  exit /b 1
)
if defined UV_CACHE_DIR if not exist "%UV_CACHE_DIR%" mkdir "%UV_CACHE_DIR%" >nul 2>nul
if defined UV_PYTHON_INSTALL_DIR if not exist "%UV_PYTHON_INSTALL_DIR%" mkdir "%UV_PYTHON_INSTALL_DIR%" >nul 2>nul
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
  rem Pre-install the cu128 torch build BEFORE kimodo so the heavy torch wheels come
  rem from the fast source (Aliyun mirror, official fallback) exactly once. kimodo's
  rem torch is an indirect dep (transformers/peft) with no version cap, so once a
  rem satisfying cu128 torch is present uv leaves it untouched during the editable
  rem install (verified: "no changes"). CPU mode skips this and installs the cpu
  rem backend in the CPU branch below.
  if /I not "%SETUP_DEVICE%"=="cpu" (
    call :install_cuda_torch
    if errorlevel 1 (
      echo [ERROR] CUDA torch runtime install failed.
      popd >nul
      exit /b 1
    )
  )
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
  call "%VENV_DIR%\Scripts\activate.bat" >nul 2>nul
  rem torch was already installed as the cu128 build before kimodo above. This is a
  rem safety net: only (re)install when torch is missing or not a cu128 build -- e.g.
  rem when kimodo was "already usable" and the pre-install was skipped, leaving a
  rem stale +cpu torch from a previous run.
  "%VENV_PY%" -c "import torch,sys; sys.exit(0 if torch.version.cuda is not None else 1)" >nul 2>nul
  if errorlevel 1 (
    echo [STEP] torch is not a cu128 build; installing CUDA torch...
    call :install_cuda_torch
    if errorlevel 1 (
      echo [ERROR] CUDA torch runtime install failed.
      exit /b 1
    )
  ) else (
    echo [INFO] torch already a CUDA build, skip cu128 reinstall.
  )
  echo [STEP] Installing triton-windows...
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" triton-windows
  if errorlevel 1 (
    echo [WARN] triton-windows install failed; torch.compile/Triton kernels may be unavailable.
  )
  call :validate_torch_env "cuda"
  set "CUDA_VALIDATE_RC=!ERRORLEVEL!"
  if !CUDA_VALIDATE_RC! EQU 3 (
    rem rc=3 means torch reports CUDA available but a real kernel launch failed.
    rem This is the old-architecture case (e.g. Maxwell/Pascal/Volta have no kernel
    rem in cu128 builds). Fall back to torchruntime, which detects the actual GPU
    rem architecture and installs the matching (older) CUDA build for it.
    echo [WARN] cu128 torch loads but cannot launch GPU kernels on this device.
    echo [WARN] Falling back to torchruntime to pick an architecture-matched build...
    call :install_torch_via_torchruntime
    if errorlevel 1 (
      echo [ERROR] torchruntime fallback install failed.
      exit /b 1
    )
    call :validate_torch_env "cuda"
    set "CUDA_VALIDATE_RC=!ERRORLEVEL!"
  )
  if !CUDA_VALIDATE_RC! NEQ 0 (
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

:print_environment
rem Diagnostics printed at setup start to make platform/GPU issues easy to debug.
echo [ENV] ============ environment ============
echo [ENV] OS: %OS%  PROCESSOR_ARCHITECTURE=%PROCESSOR_ARCHITECTURE%
echo [ENV] SETUP_DEVICE=%SETUP_DEVICE%
echo [ENV] ROOT_DIR=%ROOT_DIR%
echo [ENV] UV_DEFAULT_INDEX=%UV_DEFAULT_INDEX%
echo [ENV] UV_INDEX_URL=%UV_INDEX_URL%
echo [ENV] PIP_INDEX_URL=%PIP_INDEX_URL%
echo [ENV] KIMODO_SETUP_DEVICE=%KIMODO_SETUP_DEVICE%  KIMODO_TEST_SETUP_DEVICE=%KIMODO_TEST_SETUP_DEVICE%
echo [ENV] uv cache dir (effective):
"%UV_BIN%" cache dir 2>nul && echo. >nul || echo [ENV]   ^(uv cache dir query failed^)
echo [ENV] --- GPU (Win32_VideoController) ---
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_VideoController | ForEach-Object { '[ENV]   ' + $_.Name }" 2>nul
echo [ENV] --- NVIDIA driver (nvidia-smi) ---
where nvidia-smi >nul 2>nul && (nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>nul) || echo [ENV]   nvidia-smi not found ^(no NVIDIA driver, or not on PATH^)
echo [ENV] =====================================
exit /b 0

:install_cuda_torch
rem Install the cu128 torch/vision/audio build. If the Aliyun mirror is configured
rem AND pings close (we are on a CN network), use it via --find-links (flat wheel
rem listing, ~2x faster from CN). Otherwise -- mirror unset, ping too high, ping
rem failed, or the mirror install errors -- use --torch-backend cu128 (official
rem download.pytorch.org index). Dependencies always come from the fast PyPI mirror
rem in UV_DEFAULT_INDEX. --reinstall-package replaces any stale +cpu torch.
if defined TORCH_FINDLINKS (
  call :mirror_ping_ok
  if not errorlevel 1 (
    echo [STEP] Installing cu128 torch from mirror: %TORCH_FINDLINKS%
    "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --find-links "%TORCH_FINDLINKS%" --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0
    if not errorlevel 1 exit /b 0
    echo [WARN] cu128 torch install from mirror failed; falling back to official index.
  ) else (
    echo [INFO] mirror %TORCH_MIRROR_PING_HOST% ping too high/unreachable; using official index.
  )
)
echo [STEP] Installing cu128 torch from official index (torch-backend cu128)...
"%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" --torch-backend cu128 --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio torch torchvision torchaudio
if errorlevel 1 exit /b 1
exit /b 0

:mirror_ping_ok
rem Returns 0 if average ping to TORCH_MIRROR_PING_HOST is <= TORCH_MIRROR_MAX_PING_MS,
rem else 1 (including ping failure). Uses Test-Connection so it is locale-independent.
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $a=(Test-Connection -ComputerName '%TORCH_MIRROR_PING_HOST%' -Count 3 -ErrorAction Stop | Measure-Object -Property ResponseTime -Average).Average; if ($a -le %TORCH_MIRROR_MAX_PING_MS%) { '1' } else { '0' } } catch { '0' }"`) do set "PING_OK=%%P"
echo [INFO] mirror ping check: host=%TORCH_MIRROR_PING_HOST% threshold=%TORCH_MIRROR_MAX_PING_MS%ms ok=%PING_OK%
if "%PING_OK%"=="1" exit /b 0
exit /b 1

:install_torch_via_torchruntime
rem Fallback path: cu128 produced a torch that loads but cannot launch kernels on
rem this GPU (old architecture). torchruntime detects the actual GPU and installs
rem the matching CUDA build. We do NOT pin versions here: pinning is what makes
rem torchruntime misdetect the platform; unpinned lets it pick the right build.
rem Index env vars are cleared so torchruntime's own --index-url is the sole index.
echo [STEP] Ensuring torchruntime helper...
"%VENV_PY%" -c "import torchruntime" >nul 2>nul
if errorlevel 1 (
  "%UV_BIN%" pip install --python "%VENV_PY%" --default-index "%UV_DEFAULT_INDEX%" torchruntime
  if errorlevel 1 (
    echo [ERROR] Failed to install torchruntime.
    exit /b 1
  )
)
"%VENV_PY%" -c "import torch" >nul 2>nul
if not errorlevel 1 (
  "%UV_BIN%" pip uninstall --python "%VENV_PY%" torch torchvision torchaudio >nul 2>nul
)
setlocal
set "UV_DEFAULT_INDEX="
set "UV_INDEX_URL="
set "UV_EXTRA_INDEX_URL="
set "PIP_INDEX_URL="
set "PIP_EXTRA_INDEX_URL="
echo [STEP] Installing architecture-matched torch via torchruntime --uv...
"%VENV_PY%" -m torchruntime install --uv torch torchvision torchaudio
if errorlevel 1 (
  endlocal
  exit /b 1
)
endlocal
exit /b 0

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
rem is_available() alone is not enough: an architecture mismatch (e.g. a Maxwell/
rem Pascal card with a cu128 build) reports available=True yet fails the moment a
rem real kernel launches with "no kernel image is available for execution".
rem Launch a tiny real kernel to catch that here instead of at inference time.
rem rc=3 signals "loadable but cannot run kernels" so the caller can fall back.
"%VENV_PY%" -c "import torch,sys; t=torch.zeros(8,device='cuda'); (t+1).sum().item(); torch.cuda.synchronize(); print('kernel_ok'); sys.exit(0)" 2>nul
if errorlevel 1 (
  echo [WARN] GPU kernel launch test failed despite cuda being reported available.
  exit /b 3
)
echo [OK] CUDA torch runtime validated (kernel launch succeeded).
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


