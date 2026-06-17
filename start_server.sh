#!/usr/bin/env bash
# Linux entry point, equivalent of run_server.bat (main-chain only). Unity's
# BridgeLauncherResolver looks for start_server.sh / run_server.sh on Linux.
#
# Flow: parse args -> resolve model alias -> setup phase -> download phase ->
# preflight import check -> configure env -> launch bridge -> watchdog.
#
# Args: [--model <name>] [--highvram] [--output console|file] [--log <path>]
#       [--models-root <dir>] [--venv <path>] [--device cpu|cuda|cuda:N]
#       [--force-setup] [--config-only]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
LOG_DIR="${ROOT_DIR}/log"
BASH_DIR="${ROOT_DIR}/bash"
RECYCLE_DIR="${ROOT_DIR}/archive/recycle"
# shellcheck source=/dev/null
source "${BASH_DIR}/common_env.sh"

SETUP_SH="${BASH_DIR}/setup.sh"
DOWNLOAD_SH="${BASH_DIR}/download_model.sh"
RESOLVE_MODEL_ALIAS_SH="${BASH_DIR}/resolve_model_alias.sh"
LAUNCH_BRIDGE_SH="${BASH_DIR}/launch_bridge.sh"
RUN_SETUP_PHASE_SH="${BASH_DIR}/run_setup_phase.sh"
WATCHDOG_BRIDGE_SH="${BASH_DIR}/watchdog_bridge.sh"

SETUP_SENTINEL="${ROOT_DIR}/.setup.complete"
SETUP_LOCK="${ROOT_DIR}/.setup.lock"
PORT_FILE="${ROOT_DIR}/serverport"
BRIDGE_PID_FILE="${ROOT_DIR}/.bridge.pid"

LOG_NAME_SETUP="setup.log"
LOG_NAME_DOWNLOAD="download_model.log"
BOOTSTRAP_LOG_PATH="${LOG_DIR}/bridge_server.log"
BRIDGE_MESSAGE_LOG_PATH="${LOG_DIR}/bridge_message.log"
WATCHDOG_LOG_PATH="${LOG_DIR}/watchdog.log"

MODEL_NAME="Kimodo-SOMA-RP-v1"
HIGHVRAM=0
OUTPUT_MODE="console"
LOG_PATH="${LOG_DIR}/run_server.log"
MODELS_ROOT="${KIMODO_MODELS_ROOT:-}"
CPU_TEXT_ENCODER="${KIMODO_CPU_TEXT_ENCODER:-gguf}"
GGUF_MODEL_PATH="${KIMODO_GGUF_MODEL_PATH:-}"
GGUF_CTX="${KIMODO_GGUF_CTX:-}"
USE_CPU_GGUF=0
VENV_PATH_ARG=""
VENV_PY=""
USING_EXTERNAL_MODELS=0
USING_EXTERNAL_VENV=0
RUN_DEVICE=""
SETUP_DEVICE_MODE="auto"
TEXT_ENCODER_DEVICE_MODE="${TEXT_ENCODER_DEVICE:-}"
CONFIG_ONLY="${KIMODO_CONFIG_ONLY:-0}"
WATCHDOG_INTERVAL_SEC="${KIMODO_WATCHDOG_STARTUP_INTERVAL_SEC:-1}"
WATCHDOG_MAX_FAILS="${KIMODO_WATCHDOG_STARTUP_MAX_FAILS:-180}"
WATCHDOG_RUNTIME_INTERVAL_SEC="${KIMODO_WATCHDOG_RUNTIME_INTERVAL_SEC:-1}"
WATCHDOG_IDLE_NOLOG_MAX="${KIMODO_WATCHDOG_IDLE_NOLOG_MAX:-300}"
OUTPUT_MODE_DEFAULT_DEVICE_DONE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL_NAME="$2"; shift 2 ;;
    --highvram) HIGHVRAM=1; shift ;;
    --output) OUTPUT_MODE="$2"; shift 2 ;;
    --log) LOG_PATH="$2"; shift 2 ;;
    --models-root) MODELS_ROOT="$2"; shift 2 ;;
    --venv) VENV_PATH_ARG="$2"; shift 2 ;;
    --device) RUN_DEVICE="$2"; shift 2 ;;
    --force-setup) common_archive_file "${SETUP_SENTINEL}" "${RECYCLE_DIR}"; shift ;;
    --config-only) CONFIG_ONLY=1; shift ;;
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

if [[ -n "${VENV_PATH_ARG}" ]]; then
  VENV_PY="$(common_resolve_venv_python "${VENV_PATH_ARG}")" || exit 1
  USING_EXTERNAL_VENV=1
  echo "[INFO] Using external venv python: ${VENV_PY}"
fi

mkdir -p "${LOG_DIR}" >/dev/null 2>&1 || true
[[ -z "${MODELS_ROOT}" ]] && MODELS_ROOT="${ROOT_DIR}/models"
MODELS_ROOT="$(cd "${MODELS_ROOT}" >/dev/null 2>&1 && pwd || echo "${MODELS_ROOT}")"
if [[ "${MODELS_ROOT}" != "${ROOT_DIR}/models" ]]; then
  USING_EXTERNAL_MODELS=1
fi
if [[ "${USING_EXTERNAL_MODELS}" == "1" ]]; then
  if [[ ! -d "${MODELS_ROOT}" ]]; then
    echo "[ERROR] External models root not found: ${MODELS_ROOT}"
    exit 1
  fi
  echo "[INFO] Using external models root: ${MODELS_ROOT}"
else
  mkdir -p "${MODELS_ROOT}" >/dev/null 2>&1 || true
  echo "[INFO] Using runtime models root: ${MODELS_ROOT}"
fi

for f in "${RESOLVE_MODEL_ALIAS_SH}" "${LAUNCH_BRIDGE_SH}" "${RUN_SETUP_PHASE_SH}" "${DOWNLOAD_SH}" "${WATCHDOG_BRIDGE_SH}"; do
  if [[ ! -f "${f}" ]]; then
    echo "[ERROR] Missing required script: ${f}"
    exit 1
  fi
done

if [[ -f "${SETUP_LOCK}" ]]; then
  echo "[WARN] Found stale setup lock, archiving: ${SETUP_LOCK}"
  common_archive_file "${SETUP_LOCK}" "${RECYCLE_DIR}"
fi

# Resolve model alias to canonical name.
alias_out="$(bash "${RESOLVE_MODEL_ALIAS_SH}" "${MODEL_NAME}")" || exit 1
MODEL_NAME="$(sed -n 's/^MODEL_NAME=//p' <<<"${alias_out}")"
MODEL_RUN_NAME="${MODEL_NAME}"

if [[ "${USING_EXTERNAL_VENV}" == "0" && -f "${SETUP_LOCK}" ]]; then
  echo "[ERROR] setup is running: ${SETUP_LOCK}"
  exit 1
fi
# Device handling. cpu forces cpu setup + cpu text encoder; cuda variants enable
# auto text encoder. Empty device leaves auto text encoder and auto setup.
if [[ -n "${RUN_DEVICE}" ]]; then
  if [[ "${RUN_DEVICE,,}" == "cpu" ]]; then
    SETUP_DEVICE_MODE="cpu"
    TEXT_ENCODER_DEVICE_MODE="cpu"
  elif [[ "${RUN_DEVICE,,}" == "cuda" ]]; then
    RUN_DEVICE="cuda:0"
    [[ -z "${TEXT_ENCODER_DEVICE_MODE}" ]] && TEXT_ENCODER_DEVICE_MODE="auto"
  elif [[ "${RUN_DEVICE,,}" == cuda* ]]; then
    [[ -z "${TEXT_ENCODER_DEVICE_MODE}" ]] && TEXT_ENCODER_DEVICE_MODE="auto"
  else
    echo "[ERROR] Invalid --device value: ${RUN_DEVICE}"
    echo "[ERROR] Allowed values: cpu | cuda | cuda:0 ..."
    exit 1
  fi
else
  [[ -z "${TEXT_ENCODER_DEVICE_MODE}" ]] && TEXT_ENCODER_DEVICE_MODE="auto"
fi
echo "[INFO] Expected setup mode: ${SETUP_DEVICE_MODE}"

if [[ "${HIGHVRAM}" == "1" ]]; then
  KIMODO_LLM2VEC_DIR="${MODELS_ROOT}/Meta-Llama-3-8B-Instruct"
  TEXT_ENCODERS_DIR="${MODELS_ROOT}"
  KIMODO_LLM2VEC_PEFT_DIR="${MODELS_ROOT}/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised"
else
  KIMODO_LLM2VEC_DIR="${MODELS_ROOT}/KIMODO-Meta3_llm2vec_NF4"
  TEXT_ENCODERS_DIR=""
  KIMODO_LLM2VEC_PEFT_DIR=""
fi
[[ -z "${GGUF_MODEL_PATH}" ]] && GGUF_MODEL_PATH="${MODELS_ROOT}/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF"

if [[ -f "${PORT_FILE}" ]]; then
  echo "[WARN] Found existing serverport, archiving stale file before fresh launch."
  common_archive_file "${PORT_FILE}" "${RECYCLE_DIR}"
fi

# ---- setup phase ------------------------------------------------------------
bash "${RUN_SETUP_PHASE_SH}" "${ROOT_DIR}" "${OUTPUT_MODE}" "${USING_EXTERNAL_VENV}" \
  "${SETUP_SENTINEL}" "${SETUP_SH}" "${LOG_DIR}/${LOG_NAME_SETUP}" "${SETUP_DEVICE_MODE}" || exit 1

# Resolve venv python before the download phase so download_model.sh can probe VRAM.
[[ -z "${VENV_PY}" ]] && VENV_PY="${SOURCE_ROOT}/.venv/bin/python"
if [[ ! -x "${VENV_PY}" ]]; then
  echo "[ERROR] Missing venv python: ${VENV_PY}"
  exit 1
fi

# ---- download phase ---------------------------------------------------------
if [[ -n "${RUN_DEVICE}" && "${RUN_DEVICE,,}" == "cpu" && "${CPU_TEXT_ENCODER,,}" == "gguf" ]]; then
  USE_CPU_GGUF=1
fi
if [[ "${USING_EXTERNAL_MODELS}" == "1" ]]; then
  echo "[STEP] External models mode enabled, skip download_model."
else
  echo "[STEP] Downloading model assets for model=${MODEL_NAME} highvram=${HIGHVRAM}..."
  dl_args=(--output "${OUTPUT_MODE}" --log "${LOG_DIR}/${LOG_NAME_DOWNLOAD}"
    --unlock-stale --model "${MODEL_RUN_NAME}" --venv "${VENV_PY}")
  [[ "${HIGHVRAM}" == "1" ]] && dl_args+=(--highvram)
  [[ "${USE_CPU_GGUF}" == "1" ]] && dl_args+=(--download-gguf)
  bash "${DOWNLOAD_SH}" "${dl_args[@]}" || exit 1
fi

# ---- preflight --------------------------------------------------------------
echo "[STEP] Preflight runtime import check..."
if ! "${VENV_PY}" -c "import torch, kimodo, motion_correction; print('torch='+torch.__version__); print('cuda='+str(torch.version.cuda))"; then
  echo "[ERROR] Runtime preflight failed: cannot import torch/kimodo/motion_correction."
  echo "[ERROR] Please rerun setup from auto mode."
  exit 1
fi
# ---- model file presence checks ---------------------------------------------
MODEL_DIR_NAME="${MODEL_NAME}"
if [[ ! -f "${MODELS_ROOT}/${MODEL_DIR_NAME}/model.safetensors" ]]; then
  echo "[ERROR] Missing model file: ${MODELS_ROOT}/${MODEL_DIR_NAME}/model.safetensors"
  exit 1
fi

if [[ "${USE_CPU_GGUF}" == "1" ]]; then
  if [[ ! -e "${GGUF_MODEL_PATH}" ]]; then
    echo "[ERROR] CPU gguf mode enabled but path missing: ${GGUF_MODEL_PATH}"
    exit 1
  fi
  GGUF_MODEL_FILE=""
  if [[ "${GGUF_MODEL_PATH}" == *.gguf ]]; then
    GGUF_MODEL_FILE="${GGUF_MODEL_PATH}"
  else
    GGUF_MODEL_FILE="$(find "${GGUF_MODEL_PATH}" -type f -name '*.gguf' 2>/dev/null | head -n 1)"
  fi
  if [[ -z "${GGUF_MODEL_FILE}" ]]; then
    echo "[ERROR] CPU gguf mode enabled but no .gguf found under: ${GGUF_MODEL_PATH}"
    exit 1
  fi
  export KIMODO_GGUF_MODEL_PATH="${GGUF_MODEL_FILE}"
elif [[ "${HIGHVRAM}" == "1" ]]; then
  if [[ ! -f "${MODELS_ROOT}/Meta-Llama-3-8B-Instruct/model.safetensors.index.json" && ! -f "${MODELS_ROOT}/Meta-Llama-3-8B-Instruct/model.safetensors" ]]; then
    echo "[ERROR] Missing Meta-Llama model under ${MODELS_ROOT}/Meta-Llama-3-8B-Instruct"
    exit 1
  fi
  if [[ ! -f "${KIMODO_LLM2VEC_PEFT_DIR}/adapter_model.safetensors" && ! -f "${KIMODO_LLM2VEC_PEFT_DIR}/model.safetensors" ]]; then
    echo "[ERROR] Missing LLM2Vec PEFT model under ${KIMODO_LLM2VEC_PEFT_DIR}"
    exit 1
  fi
else
  if [[ ! -f "${KIMODO_LLM2VEC_DIR}/model.safetensors" ]]; then
    echo "[ERROR] Missing text encoder model: ${KIMODO_LLM2VEC_DIR}/model.safetensors"
    exit 1
  fi
fi

# ---- runtime environment ----------------------------------------------------
export PYTHONPATH="${SOURCE_ROOT}"
export KIMODO_ROOT_PATH="${ROOT_DIR}"
export CHECKPOINT_DIR="${MODELS_ROOT}"
export LOCAL_CACHE="true"
export KIMODO_LLM2VEC_DIR TEXT_ENCODERS_DIR KIMODO_LLM2VEC_PEFT_DIR
if [[ "${USE_CPU_GGUF}" == "1" ]]; then
  export TEXT_ENCODER_MODE="api"
  export TEXT_ENCODER_API_BACKEND="llama"
  export KIMODO_CPU_TEXT_ENCODER="gguf"
  [[ -n "${GGUF_CTX}" ]] && export KIMODO_GGUF_CTX="${GGUF_CTX}"
  export TEXT_ENCODER_DEVICE="cpu"
else
  export TEXT_ENCODER_MODE="local"
  export TEXT_ENCODER="llm2vec"
  export TEXT_ENCODER_DEVICE="${TEXT_ENCODER_DEVICE_MODE}"
fi
echo "[INFO] Runtime device: ${RUN_DEVICE:-<auto>}"
echo "[INFO] Text encoder device: ${TEXT_ENCODER_DEVICE}"
if [[ "${USE_CPU_GGUF}" == "1" ]]; then
  echo "[INFO] CPU text encoder mode: gguf"
  echo "[INFO] GGUF model path: ${KIMODO_GGUF_MODEL_PATH}"
fi

export HF_HOME="${ROOT_DIR}/hf_cache"
export TRANSFORMERS_CACHE="${HF_HOME}/transformers"
export HF_HUB_CACHE="${HF_HOME}/hub"
export HUGGINGFACE_HUB_CACHE="${HF_HOME}/hub"
export TRANSFORMERS_OFFLINE=1
export HF_HUB_OFFLINE=1
export HF_DATASETS_OFFLINE=1
export PYTHONUNBUFFERED=1
mkdir -p "${TRANSFORMERS_CACHE}" "${HUGGINGFACE_HUB_CACHE}" >/dev/null 2>&1 || true

if [[ "${CONFIG_ONLY}" == "1" ]]; then
  echo "[OK] Config-only completed. Bridge not started."
  exit 0
fi

export KIMODO_IDLE_TIMEOUT_SEC="${KIMODO_IDLE_TIMEOUT_SEC:-600}"
[[ -f "${BRIDGE_PID_FILE}" ]] && common_archive_file "${BRIDGE_PID_FILE}" "${RECYCLE_DIR}"

if [[ "${OUTPUT_MODE,,}" == "file" ]]; then
  echo "[INFO] run_server log: ${LOG_PATH}"
  echo "[INFO] bridge server log: ${BOOTSTRAP_LOG_PATH}"
  echo "[INFO] bridge message log: ${BRIDGE_MESSAGE_LOG_PATH}"
  echo "[INFO] watchdog log: ${WATCHDOG_LOG_PATH}"
  : > "${LOG_PATH}"
  [[ -f "${BOOTSTRAP_LOG_PATH}" ]] && common_archive_file "${BOOTSTRAP_LOG_PATH}" "${RECYCLE_DIR}"
  : > "${BOOTSTRAP_LOG_PATH}"
  [[ -f "${BRIDGE_MESSAGE_LOG_PATH}" ]] && common_archive_file "${BRIDGE_MESSAGE_LOG_PATH}" "${RECYCLE_DIR}"
  : > "${BRIDGE_MESSAGE_LOG_PATH}"
  [[ -f "${WATCHDOG_LOG_PATH}" ]] && common_archive_file "${WATCHDOG_LOG_PATH}" "${RECYCLE_DIR}"
  : > "${WATCHDOG_LOG_PATH}"
fi

# ---- launch bridge ----------------------------------------------------------
launch_args=(--python "${VENV_PY}" --root "${ROOT_DIR}" --model "${MODEL_RUN_NAME}"
  --bridge-log "${BOOTSTRAP_LOG_PATH}" --bridge-message-log "${BRIDGE_MESSAGE_LOG_PATH}"
  --pid-file "${BRIDGE_PID_FILE}" --output-mode "${OUTPUT_MODE}")
if [[ -n "${RUN_DEVICE}" ]]; then
  launch_args+=(--device "${RUN_DEVICE}")
fi
bash "${LAUNCH_BRIDGE_SH}" "${launch_args[@]}" || {
  echo "[ERROR] Failed to start bridge server process."; exit 1; }

SERVER_PID=""
[[ -f "${BRIDGE_PID_FILE}" ]] && SERVER_PID="$(head -n 1 "${BRIDGE_PID_FILE}" 2>/dev/null | tr -d '[:space:]')"
if [[ -z "${SERVER_PID}" ]]; then
  echo "[ERROR] Missing bridge PID in ${BRIDGE_PID_FILE}"
  exit 1
fi

# ---- watchdog ---------------------------------------------------------------
bash "${WATCHDOG_BRIDGE_SH}" "${ROOT_DIR}" "${SERVER_PID}" "${PORT_FILE}" \
  "${BOOTSTRAP_LOG_PATH}" "${WATCHDOG_INTERVAL_SEC}" "${WATCHDOG_MAX_FAILS}" \
  "${WATCHDOG_RUNTIME_INTERVAL_SEC}" "${WATCHDOG_IDLE_NOLOG_MAX}"
RC=$?
common_archive_file "${BRIDGE_PID_FILE}" "${RECYCLE_DIR}"
exit "${RC}"
