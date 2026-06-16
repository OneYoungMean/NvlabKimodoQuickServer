#!/usr/bin/env bash
# Linux equivalent of run_setup_phase.bat. Validates setup completeness by
# invoking setup.sh with the requested device mode. External-venv mode skips it.
#
# Usage: run_setup_phase.sh <root_dir> <output_mode> <using_external_venv> \
#            <setup_sentinel> <setup_sh> <setup_log_path> <setup_device>
set -euo pipefail

ROOT_DIR="${1:-}"
OUTPUT_MODE="${2:-console}"
USING_EXTERNAL_VENV="${3:-0}"
SETUP_SENTINEL="${4:-}"
SETUP_SH="${5:-}"
SETUP_LOG_PATH="${6:-}"
SETUP_DEVICE="${7:-auto}"

LOG_DIR="${ROOT_DIR}/log"
mkdir -p "${LOG_DIR}" >/dev/null 2>&1 || true
[[ -z "${SETUP_LOG_PATH}" ]] && SETUP_LOG_PATH="${LOG_DIR}/setup.log"
# Only "cpu" and "auto" are valid; anything else normalizes to auto.
if [[ "${SETUP_DEVICE,,}" != "cpu" ]]; then
  SETUP_DEVICE="auto"
fi

if [[ "${USING_EXTERNAL_VENV}" == "1" ]]; then
  echo "[STEP] External venv mode enabled, skip setup."
  exit 0
fi

echo "[STEP] Validating setup completeness for mode=${SETUP_DEVICE}..."
KIMODO_SETUP_DEVICE="${SETUP_DEVICE}" \
  bash "${SETUP_SH}" --output "${OUTPUT_MODE}" --log "${SETUP_LOG_PATH}"
exit $?
