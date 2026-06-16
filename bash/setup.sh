#!/usr/bin/env bash
# Linux equivalent of setup.bat (main-chain only). Orchestrates the build env:
# checks/updates the sentinel, holds a lock, runs setup_buildenv_impl.sh, then
# records setup_mode + torch_runtime into the sentinel.
#
# Device mode comes from KIMODO_SETUP_DEVICE (or KIMODO_TEST_SETUP_DEVICE),
# normalized to "cpu" or "auto". Args: [--output console|file] [--log <path>] [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
LOG_DIR="${ROOT_DIR}/log"
RECYCLE_DIR="${ROOT_DIR}/archive/recycle"
LOCK_FILE="${ROOT_DIR}/.setup.lock"
SENTINEL="${ROOT_DIR}/.setup.complete"
SETUP_BUILD_IMPL="${SCRIPT_DIR}/setup_buildenv_impl.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_env.sh"

OUTPUT_MODE="console"
LOG_PATH="${LOG_DIR}/setup.log"

REQUESTED_SETUP_MODE="${KIMODO_SETUP_DEVICE:-${KIMODO_TEST_SETUP_DEVICE:-}}"
if [[ "${REQUESTED_SETUP_MODE,,}" == "cpu" ]]; then
  REQUESTED_SETUP_MODE="cpu"
else
  REQUESTED_SETUP_MODE="auto"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_MODE="$2"; shift 2 ;;
    --log) LOG_PATH="$2"; shift 2 ;;
    --force) common_archive_file "${SENTINEL}" "${RECYCLE_DIR}"; shift ;;
    *) shift ;;
  esac
done

SOURCE_ROOT=""
if [[ -f "${ROOT_DIR}/pyproject.toml" ]]; then
  SOURCE_ROOT="${ROOT_DIR}"
elif [[ -f "${ROOT_DIR}/kimodo/pyproject.toml" ]]; then
  SOURCE_ROOT="${ROOT_DIR}/kimodo"
fi
if [[ -z "${SOURCE_ROOT}" ]]; then
  echo "[ERROR] Invalid project root: ${ROOT_DIR}"
  exit 1
fi
mkdir -p "${LOG_DIR}" >/dev/null 2>&1 || true

if [[ -f "${LOCK_FILE}" ]]; then
  echo "[ERROR] setup already running: ${LOCK_FILE}"
  exit 1
fi

# Sentinel check: skip if a completed setup matches the requested mode.
if [[ -f "${SENTINEL}" ]]; then
  SENTINEL_DEVICE=""
  SENTINEL_TORCH_RUNTIME=""
  while IFS='=' read -r k v; do
    case "${k}" in
      setup_mode) SENTINEL_DEVICE="${v}" ;;
      torch_runtime) SENTINEL_TORCH_RUNTIME="${v}" ;;
    esac
  done < "${SENTINEL}"
  if [[ "${SENTINEL_DEVICE,,}" == "${REQUESTED_SETUP_MODE,,}" ]]; then
    if [[ -n "${SENTINEL_TORCH_RUNTIME}" ]]; then
      echo "[INFO] setup already completed: ${SENTINEL} (mode=${SENTINEL_DEVICE}, torch=${SENTINEL_TORCH_RUNTIME})"
    else
      echo "[INFO] setup already completed: ${SENTINEL} (mode=${SENTINEL_DEVICE})"
    fi
    exit 0
  fi
  [[ -z "${SENTINEL_DEVICE}" ]] && SENTINEL_DEVICE="unknown"
  echo "[INFO] setup sentinel mode mismatch (found=${SENTINEL_DEVICE}, want=${REQUESTED_SETUP_MODE}), re-running setup."
  common_archive_file "${SENTINEL}" "${RECYCLE_DIR}"
fi

{ echo "started=$(date '+%Y-%m-%d %H:%M:%S')"; echo "root=\"${ROOT_DIR}\""; } > "${LOCK_FILE}"

main() {
  echo "[STEP] Build env (single-thread)..."
  echo "[INFO] setup mode: ${REQUESTED_SETUP_MODE}"
  if [[ ! -f "${SETUP_BUILD_IMPL}" ]]; then
    echo "[ERROR] Missing build impl: ${SETUP_BUILD_IMPL}"
    return 1
  fi
  KIMODO_SETUP_DEVICE="${REQUESTED_SETUP_MODE}" KIMODO_BUILDENV_ONLY=1 KIMODO_SETUP_BG=1 \
    bash "${SETUP_BUILD_IMPL}"
  local build_rc=$?
  [[ "${build_rc}" != "0" ]] && return "${build_rc}"

  local venv_py="${SOURCE_ROOT}/.venv/bin/python"
  if [[ ! -x "${venv_py}" ]]; then
    echo "[ERROR] Missing venv python: ${venv_py}"
    return 1
  fi
  PYTHONPATH="${SOURCE_ROOT}" "${venv_py}" -c "import numpy, kimodo, huggingface_hub, safetensors, motion_correction" || {
    echo "[ERROR] Runtime import check failed."; return 1; }

  local torch_runtime
  torch_runtime="$("${venv_py}" -c "import torch; print('cuda' if torch.version.cuda is not None else 'cpu')" 2>/dev/null || echo unknown)"
  [[ -z "${torch_runtime}" ]] && torch_runtime="unknown"

  {
    echo "setup_time=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "setup_mode=${REQUESTED_SETUP_MODE}"
    echo "torch_runtime=${torch_runtime}"
    echo "root_dir=\"${ROOT_DIR}\""
    echo "source_root=\"${SOURCE_ROOT}\""
  } > "${SENTINEL}"

  echo "[OK] setup complete."
  return 0
}

if [[ "${OUTPUT_MODE,,}" == "file" ]]; then
  main > "${LOG_PATH}" 2>&1
  RC=$?
  common_archive_file "${LOCK_FILE}" "${RECYCLE_DIR}"
  [[ "${RC}" == "0" ]] && echo "[INFO] setup log: ${LOG_PATH}"
  exit "${RC}"
fi

main
RC=$?
common_archive_file "${LOCK_FILE}" "${RECYCLE_DIR}"
exit "${RC}"
