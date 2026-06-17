#!/usr/bin/env bash
# Linux equivalent of setup_buildenv_impl.bat (main-chain only).
#
# Differences from the Windows .bat, per the agreed scope:
#  - Runtime tools come from the system PATH. If uv is missing we install it over
#    the network (curl | sh); no local portable exe, no local cache override.
#  - git/git-lfs are expected on PATH (installed via the distro package manager
#    if absent is the operator's responsibility; we only check and instruct).
#  - No test-injection hooks (KIMODO_TEST_INJECT_*), no recovery-flag scenarios.
#  - CUDA validation is SOFTENED to match the .bat change: a valid cu128 build on
#    a machine without usable CUDA is accepted (runs on CPU) instead of failing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
RUN_MARKER="${ROOT_DIR}/run"

SOURCE_ROOT=""
if [[ -f "${ROOT_DIR}/kimodo/pyproject.toml" ]]; then
  SOURCE_ROOT="${ROOT_DIR}/kimodo"
elif [[ -f "${ROOT_DIR}/pyproject.toml" ]]; then
  SOURCE_ROOT="${ROOT_DIR}"
fi
if [[ -z "${SOURCE_ROOT}" ]]; then
  echo "[ERROR] Invalid project root: ${ROOT_DIR}"
  exit 1
fi
if [[ ! -f "${SOURCE_ROOT}/pyproject.toml" ]]; then
  echo "[ERROR] Missing pyproject.toml under: ${SOURCE_ROOT}"
  exit 1
fi
if [[ ! -f "${SOURCE_ROOT}/kimodo/model/load_model.py" ]]; then
  echo "[ERROR] Invalid source layout under: ${SOURCE_ROOT}"
  exit 1
fi

mkdir -p "${ROOT_DIR}/log" >/dev/null 2>&1 || true

# ---- tunables (env-overridable), mirroring the .bat defaults ----------------
UV_CONCURRENT_DOWNLOADS="${KIMODO_UV_CONCURRENT_DOWNLOADS:-16}"
export UV_CONCURRENT_DOWNLOADS
TORCH_FINDLINKS="${KIMODO_TORCH_FINDLINKS-https://mirrors.aliyun.com/pytorch-wheels/cu128}"
TORCH_MIRROR_PING_HOST="${KIMODO_TORCH_MIRROR_PING_HOST:-mirrors.aliyun.com}"
TORCH_MIRROR_MAX_PING_MS="${KIMODO_TORCH_MIRROR_MAX_PING_MS:-50}"
LOCAL_WHEELS_DIR="${ROOT_DIR}/wheels"
ANTLR4_WHEEL="${LOCAL_WHEELS_DIR}/antlr4_python3_runtime-4.9.3-py3-none-any.whl"
BITSANDBYTES_REQUIRED="0.49.2"
PYTHON_SPEC="3.12"

SETUP_DEVICE="${KIMODO_SETUP_DEVICE:-${KIMODO_TEST_SETUP_DEVICE:-auto}}"
[[ "${SETUP_DEVICE,,}" == "cuda" ]] && SETUP_DEVICE="auto"

UV_DEFAULT_INDEX=""
VENV_DIR="${SOURCE_ROOT}/.venv"
VENV_PY="${VENV_DIR}/bin/python"
print_environment() {
  echo "[ENV] ============ environment ============"
  echo "[ENV] OS: $(uname -s)  ARCH=$(uname -m)"
  echo "[ENV] SETUP_DEVICE=${SETUP_DEVICE}"
  echo "[ENV] ROOT_DIR=${ROOT_DIR}"
  echo "[ENV] UV_DEFAULT_INDEX=${UV_DEFAULT_INDEX}"
  echo "[ENV] KIMODO_SETUP_DEVICE=${KIMODO_SETUP_DEVICE:-}  KIMODO_TEST_SETUP_DEVICE=${KIMODO_TEST_SETUP_DEVICE:-}"
  echo "[ENV] --- NVIDIA driver (nvidia-smi) ---"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null \
      || echo "[ENV]   nvidia-smi present but query failed"
  else
    echo "[ENV]   nvidia-smi not found (no NVIDIA driver, or not on PATH)"
  fi
  echo "[ENV] ====================================="
}

# Ensure uv is available. Prefer system PATH; if missing, install over the
# network into ~/.local/bin (per agreed policy: net install, no local cache).
ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
    echo "[INFO] Using system uv: ${UV_BIN}"
    return 0
  fi
  echo "[INFO] uv not found; installing via official installer (network)..."
  if ! command -v curl >/dev/null 2>&1; then
    echo "[ERROR] curl is required to install uv. Install curl or uv first."
    return 1
  fi
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="${HOME}/.local/bin:${PATH}"
  if command -v uv >/dev/null 2>&1; then
    UV_BIN="$(command -v uv)"
    echo "[INFO] Installed uv: ${UV_BIN}"
    return 0
  fi
  echo "[ERROR] uv installation failed."
  echo "[ERROR] Docs: https://docs.astral.sh/uv/getting-started/installation/"
  return 1
}

# git + git-lfs come from the system. We check and give an install hint.
ensure_git_lfs() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] git not found on PATH."
    echo "[HINT] Install git first, e.g.:"
    echo "       sudo apt-get update && sudo apt-get install -y git"
    return 1
  fi
  if ! command -v git-lfs >/dev/null 2>&1 && ! git lfs version >/dev/null 2>&1; then
    echo "[ERROR] git-lfs not found on PATH."
    echo "[HINT] Install git-lfs first, e.g.:"
    echo "       sudo apt-get update && sudo apt-get install -y git-lfs"
    echo "       git lfs install"
    return 1
  fi
  git lfs install --skip-repo >/dev/null 2>&1 || true
  echo "[OK] system git/git-lfs are ready."
  return 0
}

select_uv_default_index() {
  if [[ -n "${KIMODO_PIP_INDEX_URL:-}" ]]; then
    UV_DEFAULT_INDEX="${KIMODO_PIP_INDEX_URL}"
    return 0
  fi
  UV_DEFAULT_INDEX="https://pypi.org/simple"
  # Prefer the Tsinghua mirror when reachable (CN networks).
  if curl -fsS --head --max-time 2 "https://pypi.tuna.tsinghua.edu.cn/simple" >/dev/null 2>&1; then
    UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
  fi
  return 0
}

# Returns 0 if the torch mirror pings within threshold (CN network), else 1.
mirror_ping_ok() {
  local avg
  avg="$(ping -c 3 -W 2 "${TORCH_MIRROR_PING_HOST}" 2>/dev/null \
    | awk -F'/' '/rtt|round-trip/ {print $5}')"
  echo "[INFO] mirror ping check: host=${TORCH_MIRROR_PING_HOST} threshold=${TORCH_MIRROR_MAX_PING_MS}ms avg=${avg:-NA}"
  [[ -z "${avg}" ]] && return 1
  awk -v a="${avg}" -v t="${TORCH_MIRROR_MAX_PING_MS}" 'BEGIN{exit !(a<=t)}'
}
install_cuda_torch() {
  # Install cu128 torch/vision/audio. Use the Aliyun mirror via --find-links when
  # it pings close (CN network); otherwise fall back to the official cu128 index.
  if [[ -n "${TORCH_FINDLINKS}" ]]; then
    if mirror_ping_ok; then
      echo "[STEP] Installing cu128 torch from mirror: ${TORCH_FINDLINKS}"
      if "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" \
        --find-links "${TORCH_FINDLINKS}" \
        --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio \
        torch==2.11.0 torchvision==0.26.0 torchaudio==2.11.0; then
        return 0
      fi
      echo "[WARN] cu128 torch install from mirror failed; falling back to official index."
    else
      echo "[INFO] mirror ${TORCH_MIRROR_PING_HOST} ping too high/unreachable; using official index."
    fi
  fi
  echo "[STEP] Installing cu128 torch from official index (torch-backend cu128)..."
  "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" \
    --torch-backend cu128 \
    --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio \
    torch torchvision torchaudio
}

install_torch_via_torchruntime() {
  # Fallback for old GPU architectures: torchruntime detects the actual GPU and
  # installs a matching CUDA build. No version pins (pinning causes misdetection).
  echo "[STEP] Ensuring torchruntime helper..."
  if ! "${VENV_PY}" -c "import torchruntime" >/dev/null 2>&1; then
    "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" torchruntime || return 1
  fi
  if "${VENV_PY}" -c "import torch" >/dev/null 2>&1; then
    "${UV_BIN}" pip uninstall --python "${VENV_PY}" torch torchvision torchaudio >/dev/null 2>&1 || true
  fi
  echo "[STEP] Installing architecture-matched torch via torchruntime --uv..."
  env -u UV_DEFAULT_INDEX -u UV_INDEX_URL -u UV_EXTRA_INDEX_URL -u PIP_INDEX_URL -u PIP_EXTRA_INDEX_URL \
    "${VENV_PY}" -m torchruntime install --uv torch torchvision torchaudio
}

# Validate the torch runtime. Mirrors the SOFTENED .bat logic:
#   rc=0  build sane and (CUDA usable, kernel ok) OR (CUDA unavailable -> CPU ok)
#   rc=1  build broken (import fails or not a CUDA build)  -> hard fail upstream
#   rc=3  CUDA reports available but a real kernel launch fails -> caller falls
#         back to torchruntime (architecture mismatch).
validate_torch_env() {
  local mode="${1:-cuda}"
  if [[ "${mode}" == "cpu" ]]; then
    echo "[STEP] Validating CPU torch runtime..."
    if ! "${VENV_PY}" -c "import importlib,torch,sys; importlib.import_module('torch._jit_internal'); print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); sys.exit(0)"; then
      echo "[ERROR] Python environment is abnormal for CPU runtime."
      return 1
    fi
    return 0
  fi

  echo "[STEP] Validating CUDA torch runtime..."
  # Step 1: verify torch can actually be loaded (import torch + a deep internal
  # module). This catches a genuinely broken install (missing files, .so load
  # failure, incompatible build) -- that is the only hard failure. We do NOT
  # require a CUDA build here: a working CPU torch is acceptable, and whether CUDA
  # is actually usable is left to the soft checks in steps 2-3 below.
  if ! "${VENV_PY}" -c "import importlib,torch,sys; importlib.import_module('torch._jit_internal'); print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda)); sys.exit(0)"; then
    echo "[ERROR] torch cannot be loaded in this environment (broken install)."
    echo "[ERROR] Please reinstall setup with auto mode."
    return 1
  fi
  # Step 2: probe runtime CUDA availability, separately from whether torch loaded.
  # When CUDA is unavailable (no usable GPU/driver, e.g. a CPU-only or remote
  # machine, or a cpu torch build) we deliberately do NOT fail: torch runs fine on
  # CPU and the runtime (bridge_server) already falls back to CPU when
  # is_available() is False. CUDA is a soft, best-effort capability here.
  if ! "${VENV_PY}" -c "import torch,sys; sys.exit(0 if torch.cuda.is_available() else 1)" >/dev/null 2>&1; then
    echo "[WARN] CUDA not available on this machine; torch will run on CPU."
    echo "[WARN] torch loads correctly -- accepting it and skipping the GPU kernel test."
    return 0
  fi
  # Step 3: CUDA available -> launch a real kernel to catch architecture mismatch
  # (Maxwell/Pascal with a cu128 build report available but cannot run kernels).
  if ! "${VENV_PY}" -c "import torch,sys; t=torch.zeros(8,device='cuda'); (t+1).sum().item(); torch.cuda.synchronize(); print('kernel_ok'); sys.exit(0)" 2>/dev/null; then
    echo "[WARN] GPU kernel launch test failed despite cuda being reported available."
    return 3
  fi
  echo "[OK] CUDA torch runtime validated (kernel launch succeeded)."
  return 0
}

ensure_bitsandbytes() {
  local ctx="${1:-CUDA mode}"
  echo "[STEP] Ensuring bitsandbytes for ${ctx}..."
  if "${VENV_PY}" -c "import bitsandbytes as bnb; from packaging.version import Version as V; import sys; sys.exit(0 if V(getattr(bnb,'__version__','0'))>=V('0.46.1') else 1)" >/dev/null 2>&1; then
    echo "[INFO] bitsandbytes>=0.46.1 already present, skip reinstall."
    return 0
  fi
  "${UV_BIN}" pip install --python "${VENV_PY}" "bitsandbytes==${BITSANDBYTES_REQUIRED}" || {
    echo "[ERROR] Failed to install bitsandbytes for ${ctx}."; return 1; }
  "${VENV_PY}" -c "import bitsandbytes as bnb; from packaging.version import Version as V; import sys; sys.exit(0 if V(getattr(bnb,'__version__','0'))>=V('0.46.1') else 1)" || {
    echo "[ERROR] bitsandbytes version check failed after install for ${ctx}."; return 1; }
  return 0
}
run_setup() {
  print_environment

  ensure_uv || {
    echo "[ERROR] uv not found and could not be installed."; return 1; }
  ensure_git_lfs || return 1

  select_uv_default_index
  echo "[INFO] Selected uv default index: ${UV_DEFAULT_INDEX}"

  echo "[STEP] Ensuring uv-managed Python: ${PYTHON_SPEC}"
  "${UV_BIN}" python install "${PYTHON_SPEC}" || {
    echo "[ERROR] Failed to install or locate Python via uv: ${PYTHON_SPEC}"; return 1; }

  echo "[STEP] Creating/updating venv with uv..."
  "${UV_BIN}" venv "${VENV_DIR}" --python "${PYTHON_SPEC}" --allow-existing || {
    echo "[ERROR] uv venv failed."; return 1; }
  if [[ ! -x "${VENV_PY}" ]]; then
    echo "[ERROR] venv python missing: ${VENV_PY}"; return 1
  fi

  echo "[STEP] Seeding build helpers in venv..."
  "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" pip setuptools wheel || {
    echo "[ERROR] Failed to install build helpers pip/setuptools/wheel."; return 1; }

  echo "[STEP] Installing local antlr4 runtime wheel..."
  if [[ ! -f "${ANTLR4_WHEEL}" ]]; then
    echo "[ERROR] Missing required local wheel: ${ANTLR4_WHEEL}"; return 1
  fi
  "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" \
    --no-index --find-links "${LOCAL_WHEELS_DIR}" --only-binary antlr4-python3-runtime \
    antlr4-python3-runtime==4.9.3 || {
    echo "[ERROR] Failed to install local antlr4 runtime wheel."; return 1; }

  echo "[STEP] Installing kimodo package with uv pip (no git extras)..."
  local kimodo_ok=0
  if "${VENV_PY}" -c "import importlib.metadata as m; import tqdm, huggingface_hub, safetensors; print(m.version('kimodo'))" >/dev/null 2>&1; then
    kimodo_ok=1
  fi
  if [[ "${kimodo_ok}" == "0" ]]; then
    pushd "${SOURCE_ROOT}" >/dev/null
    export SKIP_MOTION_CORRECTION_IN_SETUP=1
    if [[ "${SETUP_DEVICE,,}" != "cpu" ]]; then
      if ! install_cuda_torch; then
        echo "[ERROR] CUDA torch runtime install failed."; popd >/dev/null; return 1
      fi
    fi
    local kimodo_install_rc=0
    "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" \
      --find-links "${LOCAL_WHEELS_DIR}" --only-binary antlr4-python3-runtime \
      --editable . --no-build-isolation || kimodo_install_rc=$?
    unset SKIP_MOTION_CORRECTION_IN_SETUP
    popd >/dev/null
    if ! "${VENV_PY}" -c "import importlib.metadata as m; import tqdm, huggingface_hub, safetensors; print(m.version('kimodo'))" >/dev/null 2>&1; then
      echo "[ERROR] Failed to install kimodo package via uv pip."; return 1
    fi
    if [[ "${kimodo_install_rc}" != "0" ]]; then
      echo "[WARN] uv pip returned non-zero, but kimodo import check passed."
    fi
  else
    echo "[INFO] kimodo already usable, skip reinstall."
  fi

  if [[ "${SETUP_DEVICE,,}" == "cpu" ]]; then
    export UV_TORCH_BACKEND=cpu
    echo "[STEP] Installing CPU torch runtime via uv..."
    "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" \
      --torch-backend cpu \
      --reinstall-package torch --reinstall-package torchvision --reinstall-package torchaudio \
      torch torchvision torchaudio || {
      echo "[ERROR] CPU torch runtime install failed."; return 1; }
    validate_torch_env "cpu" || {
      echo "[ERROR] CPU torch runtime validation failed."; return 1; }
    echo "[INFO] CPU mode: skip bitsandbytes/4-bit install by policy."
  else
    # torch was pre-installed as cu128 above; only (re)install if missing/not cuda.
    if ! "${VENV_PY}" -c "import torch,sys; sys.exit(0 if torch.version.cuda is not None else 1)" >/dev/null 2>&1; then
      echo "[STEP] torch is not a cu128 build; installing CUDA torch..."
      install_cuda_torch || { echo "[ERROR] CUDA torch runtime install failed."; return 1; }
    else
      echo "[INFO] torch already a CUDA build, skip cu128 reinstall."
    fi
    echo "[STEP] Installing triton (Linux)..."
    "${UV_BIN}" pip install --python "${VENV_PY}" --default-index "${UV_DEFAULT_INDEX}" triton \
      || echo "[WARN] triton install failed; torch.compile/Triton kernels may be unavailable."

    validate_torch_env "cuda"; local cuda_rc=$?
    if [[ "${cuda_rc}" == "3" ]]; then
      echo "[WARN] cu128 torch loads but cannot launch GPU kernels on this device."
      echo "[WARN] Falling back to torchruntime to pick an architecture-matched build..."
      install_torch_via_torchruntime || { echo "[ERROR] torchruntime fallback install failed."; return 1; }
      validate_torch_env "cuda"; cuda_rc=$?
    fi
    if [[ "${cuda_rc}" != "0" ]]; then
      echo "[ERROR] CUDA torch runtime validation failed."; return 1
    fi
    ensure_bitsandbytes "CUDA mode" || return 1
  fi

  echo "[STEP] Ensuring motion_correction..."
  local mc_whl_linux="${ROOT_DIR}/wheels/motion_correction-1.0.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl"
  if ! "${VENV_PY}" -c "import motion_correction" >/dev/null 2>&1; then
    if [[ -f "${mc_whl_linux}" ]]; then
      "${UV_BIN}" pip install --python "${VENV_PY}" "${mc_whl_linux}" || {
        echo "[ERROR] Failed to install motion_correction wheel: ${mc_whl_linux}"; return 1; }
    else
      echo "[ERROR] Missing motion_correction Linux wheel under: ${ROOT_DIR}/wheels"; return 1
    fi
  else
    echo "[INFO] motion_correction already present, skip reinstall."
  fi

  mkdir -p "${ROOT_DIR}/models" >/dev/null 2>&1 || true

  PYTHONPATH="${SOURCE_ROOT}" "${VENV_PY}" -c "import numpy, huggingface_hub, safetensors; import kimodo.model.load_model" || {
    echo "[ERROR] Runtime check failed: cannot import runtime deps in venv."; return 1; }

  echo "[OK] Build environment staged."
  echo "[INFO] ROOT_DIR=${ROOT_DIR}"
  echo "[INFO] SOURCE_ROOT=${SOURCE_ROOT}"
  echo "[INFO] VENV_PY=${VENV_PY}"
  return 0
}

# KIMODO_SETUP_BG mirrors the .bat: when set we log to stdout (caller redirects);
# otherwise we still log to stdout here since the Linux caller handles redirection.
run_setup
rc=$?
if [[ "${rc}" == "0" && ! -d "${RUN_MARKER}" ]]; then
  mkdir -p "${RUN_MARKER}" >/dev/null 2>&1 || true
fi
exit ${rc}
