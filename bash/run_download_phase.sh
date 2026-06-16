#!/usr/bin/env bash
# Linux equivalent of run_download_phase.bat. Skips download when using an
# external models root; otherwise delegates to download_model.sh.
#
# Usage: run_download_phase.sh <root_dir> <output_mode> <using_external_models> \
#            <highvram> <model_run_name> <model_name> <download_sh> <download_log_path>
set -euo pipefail

ROOT_DIR="${1:-}"
OUTPUT_MODE="${2:-console}"
USING_EXTERNAL_MODELS="${3:-0}"
HIGHVRAM="${4:-0}"
MODEL_RUN_NAME="${5:-}"
MODEL_NAME="${6:-}"
DOWNLOAD_SH="${7:-}"
DOWNLOAD_LOG_PATH="${8:-}"

LOG_DIR="${ROOT_DIR}/log"
mkdir -p "${LOG_DIR}" >/dev/null 2>&1 || true
[[ -z "${DOWNLOAD_LOG_PATH}" ]] && DOWNLOAD_LOG_PATH="${LOG_DIR}/download_model.log"

if [[ "${USING_EXTERNAL_MODELS}" == "1" ]]; then
  echo "[STEP] External models mode enabled, skip download_model."
  exit 0
fi

echo "[STEP] Downloading model assets for model=${MODEL_NAME} highvram=${HIGHVRAM}..."
gguf_arg=()
if [[ "${KIMODO_DOWNLOAD_GGUF:-}" == "1" ]]; then
  gguf_arg=(--download-gguf)
fi

if [[ "${HIGHVRAM}" == "1" ]]; then
  bash "${DOWNLOAD_SH}" --output "${OUTPUT_MODE}" --log "${DOWNLOAD_LOG_PATH}" \
    --unlock-stale --model "${MODEL_RUN_NAME}" --highvram "${gguf_arg[@]}"
else
  bash "${DOWNLOAD_SH}" --output "${OUTPUT_MODE}" --log "${DOWNLOAD_LOG_PATH}" \
    --unlock-stale --model "${MODEL_RUN_NAME}" "${gguf_arg[@]}"
fi
exit $?
