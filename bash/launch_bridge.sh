#!/usr/bin/env bash
# Linux equivalent of launch_bridge.ps1. Starts the bridge server python process
# in the background, redirects its output, and writes the child PID to a pid file
# (written atomically via a .tmp rename, matching the .ps1).
#
# Usage:
#   launch_bridge.sh --python <py> --root <dir> --model <name> [--device <dev>] \
#       --bridge-log <path> --bridge-message-log <path> --pid-file <path> \
#       --output-mode <console|file>
set -euo pipefail

PYTHON_PATH=""
ROOT_DIR=""
MODEL_NAME=""
DEVICE=""
BRIDGE_LOG_PATH=""
BRIDGE_MESSAGE_LOG_PATH=""
PID_FILE=""
OUTPUT_MODE="console"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --python) PYTHON_PATH="$2"; shift 2 ;;
    --root) ROOT_DIR="$2"; shift 2 ;;
    --model) MODEL_NAME="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --bridge-log) BRIDGE_LOG_PATH="$2"; shift 2 ;;
    --bridge-message-log) BRIDGE_MESSAGE_LOG_PATH="$2"; shift 2 ;;
    --pid-file) PID_FILE="$2"; shift 2 ;;
    --output-mode) OUTPUT_MODE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "${PYTHON_PATH}" || -z "${ROOT_DIR}" || -z "${MODEL_NAME}" || -z "${PID_FILE}" ]]; then
  echo "[ERROR] launch_bridge.sh missing required args." >&2
  exit 1
fi

mkdir -p "$(dirname "${PID_FILE}")" >/dev/null 2>&1 || true

# The bridge log path is also passed through the environment, matching the .ps1.
export KIMODO_BRIDGE_LOG="${BRIDGE_LOG_PATH}"

args=(-u -m kimodo.bridge.bridge_server --model "${MODEL_NAME}" --kimodo-root "${ROOT_DIR}")
if [[ -n "${DEVICE}" ]]; then
  args+=(--device "${DEVICE}")
fi

# setsid detaches the child into its own session so it survives this launcher
# exiting (the .ps1 relied on Start-Process for the same effect).
if [[ "${OUTPUT_MODE,,}" == "file" ]]; then
  setsid "${PYTHON_PATH}" "${args[@]}" \
    >"${BRIDGE_LOG_PATH}" 2>"${BRIDGE_MESSAGE_LOG_PATH}" &
else
  setsid "${PYTHON_PATH}" "${args[@]}" &
fi
child_pid=$!

tmp_pid_file="${PID_FILE}.tmp"
printf '%s\n' "${child_pid}" > "${tmp_pid_file}"
mv -f "${tmp_pid_file}" "${PID_FILE}"
exit 0
