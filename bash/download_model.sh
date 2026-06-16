#!/usr/bin/env bash
# Linux equivalent of download_model.bat (main-chain only). Syncs model repos via
# system git + git-lfs. No test-injection hooks. Mirrors the .bat's repo URLs,
# alias resolution, fallback handling, safetensor validation, and gguf handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
LOG_DIR="${ROOT_DIR}/log"
MODELS_DIR="${ROOT_DIR}/models"
RESOLVE_MODEL_ALIAS_SH="${SCRIPT_DIR}/resolve_model_alias.sh"

OUTPUT_MODE="console"
LOG_PATH="${LOG_DIR}/download_model.log"
UNLOCK_STALE=0
FORCE_SYNC=0
DOWNLOAD_GGUF="${KIMODO_DOWNLOAD_GGUF:-1}"
MODEL_NAME="Kimodo-SOMA-RP-v1"
HIGHVRAM=0

LLM2VEC_NF4_REPO_URL="${KIMODO_LLM2VEC_NF4_REPO_URL:-https://www.modelscope.cn/oneyoungmean/KIMODO-Meta3_llm2vec_NF4.git}"
LLM2VEC_NF4_REPO_URL_FALLBACK="${KIMODO_LLM2VEC_NF4_REPO_URL_FALLBACK:-https://huggingface.co/Aero-Ex/KIMODO-Meta3_llm2vec_NF4}"
GGUF_REPO_URL="${KIMODO_GGUF_REPO_URL:-https://www.modelscope.cn/LLM-Research/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF.git}"
GGUF_REPO_URL_FALLBACK="${KIMODO_GGUF_REPO_URL_FALLBACK:-https://huggingface.co/Aero-Ex/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF}"
META_LLAMA_REPO_URL="${KIMODO_META_LLAMA_REPO_URL:-https://www.modelscope.cn/models/LLM-Research/Meta-Llama-3-8B-Instruct}"
LLM2VEC_PEFT_REPO_URL="${KIMODO_LLM2VEC_PEFT_REPO_URL:-https://www.modelscope.cn/models/oneyoungmean/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_MODE="$2"; shift 2 ;;
    --log) LOG_PATH="$2"; shift 2 ;;
    --unlock-stale) UNLOCK_STALE=1; shift ;;
    --force) FORCE_SYNC=1; shift ;;
    --model) MODEL_NAME="$2"; shift 2 ;;
    --download-gguf) DOWNLOAD_GGUF=1; shift ;;
    --highvram) HIGHVRAM=1; shift ;;
    *) shift ;;
  esac
done
ensure_git_and_lfs() {
  if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] git not found on PATH."
    return 1
  fi
  if ! git lfs version >/dev/null 2>&1; then
    echo "[ERROR] git-lfs not found on PATH."
    return 1
  fi
  git lfs install --skip-repo >/dev/null 2>&1 || {
    echo "[ERROR] git lfs install failed."; return 1; }
  return 0
}

normalize_repo_url() {
  local raw="$1"
  local out="${raw}"
  if [[ "${raw}" == *"modelscope.cn/models/"* ]]; then
    local tmp="${raw}"
    tmp="${tmp/https:\/\/www.modelscope.cn\/models\//}"
    tmp="${tmp/http:\/\/www.modelscope.cn\/models\//}"
    tmp="${tmp/\/models\//}"
    tmp="${tmp/.git/}"
    out="https://www.modelscope.cn/${tmp}.git"
  elif [[ "${raw}" == https://www.modelscope.cn/* || "${raw}" == https://huggingface.co/* ]]; then
    [[ "${raw}" != *.git* ]] && out="${raw}.git"
  fi
  printf '%s' "${out}"
}

# A safetensor is "valid" if present and larger than 1KiB (matches the .bat's
# size heuristic; the .bat does not parse the header either).
validate_safetensor() {
  local f="$1"
  [[ ! -f "${f}" ]] && return 1
  local size
  size="$(stat -c %s "${f}" 2>/dev/null || echo 0)"
  [[ "${size}" -le 1024 ]] && return 1
  return 0
}

backup_dir() {
  local d="$1"
  [[ ! -e "${d}" ]] && return 0
  local bak="${d}.broken.${RANDOM}${RANDOM}"
  mv "${d}" "${bak}" || { echo "[ERROR] Failed to backup: ${d}"; return 1; }
  echo "[WARN] Backed up to: ${bak}"
  return 0
}

rotate_lock() {
  local lock="$1/.git/index.lock"
  if [[ -f "${lock}" ]]; then
    local bak="${lock}.stale.${RANDOM}${RANDOM}"
    mv "${lock}" "${bak}" || { echo "[ERROR] Failed to rotate stale lock: ${lock}"; return 1; }
    echo "[WARN] Rotated stale lock: ${bak}"
  fi
  return 0
}
ensure_gguf_presence() {
  local dir="$1"
  [[ -d "${dir}" ]] || return 1
  if find "${dir}" -type f -name '*.gguf' 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

prepare_repo() {
  local repo_dir="$1"
  [[ "${UNLOCK_STALE}" == "1" ]] && rotate_lock "${repo_dir}"
  if git -C "${repo_dir}" rev-parse --verify HEAD >/dev/null 2>&1; then
    return 0
  fi
  if [[ -f "${repo_dir}/model.safetensors" ]]; then
    echo "[WARN] Existing non-git model directory found, keep local files: ${repo_dir}"
    return 0
  fi
  backup_dir "${repo_dir}" || return 1
  return 0
}

validate_repo_safetensors() {
  local dest="$1" req="$2" lfs_inc="$3"
  local target="${dest}/${req}"
  [[ "${req}" != *.safetensors ]] && return 0
  [[ ! -f "${target}" ]] && return 0
  validate_safetensor "${target}" && return 0
  echo "[WARN] Corrupted safetensor detected: ${target}"
  local broken="${target}.broken.${RANDOM}${RANDOM}"
  mv "${target}" "${broken}" || { echo "[ERROR] Failed to archive corrupted safetensor: ${target}"; return 1; }
  echo "[WARN] Archived corrupted safetensor: ${broken}"
  git -C "${dest}" checkout HEAD -- "${req}" || return 1
  git -C "${dest}" lfs pull --include="${lfs_inc}" || return 1
  [[ ! -f "${target}" ]] && { echo "[ERROR] Missing ${req} after repair sync: ${dest}"; return 1; }
  validate_safetensor "${target}" || { echo "[ERROR] safetensors validation still failed after one-time repair: ${target}"; return 1; }
  echo "[OK] safetensors repaired: ${target}"
  return 0
}
ensure_repo() {
  local repo_url="$1" dest_dir="$2" req_file="$3" lfs_include="${4:-}"
  [[ -z "${lfs_include}" ]] && lfs_include="${req_file}"
  repo_url="$(normalize_repo_url "${repo_url}")"

  if [[ "${FORCE_SYNC}" == "0" ]]; then
    if [[ "${req_file}" == ".gguf" ]]; then
      if [[ -d "${dest_dir}" ]] && ensure_gguf_presence "${dest_dir}"; then
        echo "[INFO] Skip existing gguf model: ${dest_dir}"
        return 0
      fi
      [[ -d "${dest_dir}" ]] && echo "[WARN] Existing GGUF directory has no .gguf files, forcing sync: ${dest_dir}"
    else
      if [[ -f "${dest_dir}/${req_file}" ]]; then
        echo "[INFO] Skip existing model: ${dest_dir}"
        validate_repo_safetensors "${dest_dir}" "${req_file}" "${lfs_include}" || return 1
        return 0
      fi
    fi
  fi

  if [[ -d "${dest_dir}" && ! -d "${dest_dir}/.git" ]]; then
    backup_dir "${dest_dir}" || return 1
  fi

  if [[ ! -d "${dest_dir}" ]]; then
    echo "[STEP] Cloning ${repo_url}"
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "${repo_url}" "${dest_dir}" || return 1
  else
    prepare_repo "${dest_dir}" || return 1
    echo "[STEP] Updating existing repo: ${dest_dir}"
    if ! GIT_LFS_SKIP_SMUDGE=1 git -C "${dest_dir}" pull; then
      backup_dir "${dest_dir}" || return 1
      echo "[STEP] Re-cloning ${repo_url}"
      GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 "${repo_url}" "${dest_dir}" || return 1
    fi
  fi

  prepare_repo "${dest_dir}" || return 1
  git -C "${dest_dir}" lfs pull --include="${lfs_include}" || return 1

  if [[ "${req_file}" == ".gguf" ]]; then
    ensure_gguf_presence "${dest_dir}" || { echo "[ERROR] Missing .gguf files after sync: ${dest_dir}"; return 1; }
  else
    if [[ ! -f "${dest_dir}/${req_file}" ]]; then
      git -C "${dest_dir}" checkout HEAD -- "${req_file}" || return 1
      git -C "${dest_dir}" lfs pull --include="${lfs_include}" || return 1
    fi
    [[ ! -f "${dest_dir}/${req_file}" ]] && { echo "[ERROR] Missing ${req_file} after sync: ${dest_dir}"; return 1; }
  fi
  validate_repo_safetensors "${dest_dir}" "${req_file}" "${lfs_include}" || return 1
  return 0
}

ensure_repo_with_fallback() {
  local primary="$1" fallback="$2" dest="$3" req="$4" lfs="$5"
  if ensure_repo "${primary}" "${dest}" "${req}" "${lfs}"; then
    return 0
  fi
  [[ -z "${fallback}" ]] && return 1
  echo "[WARN] Primary repo failed, fallback to: ${fallback}"
  ensure_repo "${fallback}" "${dest}" "${req}" "${lfs}" || return 1
  echo "[OK] Fallback repo succeeded: ${fallback}"
  return 0
}

ensure_repo_any() {
  local repo="$1" dest="$2" req_a="$3" req_b="$4" lfs="$5"
  ensure_repo "${repo}" "${dest}" "${req_a}" "${lfs}" && return 0
  ensure_repo "${repo}" "${dest}" "${req_b}" "${lfs}" && return 0
  echo "[ERROR] Missing required files after sync: ${dest}"
  echo "[ERROR] Need one of: ${req_a} or ${req_b}"
  return 1
}
main() {
  mkdir -p "${LOG_DIR}" "${MODELS_DIR}" >/dev/null 2>&1 || true
  ensure_git_and_lfs || return 1

  echo "[STEP] Downloading models (single-thread)..."
  if [[ ! -f "${RESOLVE_MODEL_ALIAS_SH}" ]]; then
    echo "[ERROR] Missing model alias resolver: ${RESOLVE_MODEL_ALIAS_SH}"; return 1
  fi
  local alias_out
  alias_out="$(bash "${RESOLVE_MODEL_ALIAS_SH}" "${MODEL_NAME}")" || return 1
  local MODEL_DIR_NAME MODEL_REPO_NAME
  MODEL_NAME="$(sed -n 's/^MODEL_NAME=//p' <<<"${alias_out}")"
  MODEL_DIR_NAME="$(sed -n 's/^MODEL_DIR_NAME=//p' <<<"${alias_out}")"
  MODEL_REPO_NAME="$(sed -n 's/^MODEL_REPO_NAME=//p' <<<"${alias_out}")"

  local model_repo_url="https://www.modelscope.cn/nv-community/${MODEL_REPO_NAME}.git"
  local model_repo_url_fallback=""
  case "${MODEL_REPO_NAME}" in
    Kimodo-SOMA-RP-v1.1) model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1" ;;
    Kimodo-SMPLX-RP-v1)  model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-SMPLX-RP-v1" ;;
    Kimodo-G1-RP-v1)     model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-G1-RP-v1" ;;
    Kimodo-SOMA-SEED-v1) model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1" ;;
    Kimodo-SOMA-SEED-v1.1) model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-SOMA-SEED-v1.1" ;;
    Kimodo-G1-SEED-v1)   model_repo_url_fallback="https://huggingface.co/nvidia/Kimodo-G1-SEED-v1" ;;
  esac
  ensure_repo_with_fallback "${model_repo_url}" "${model_repo_url_fallback}" \
    "${MODELS_DIR}/${MODEL_DIR_NAME}" "model.safetensors" "*" || return 1

  if [[ "${HIGHVRAM}" == "1" ]]; then
    echo "[STEP] highvram mode enabled: full text-encoder assets"
    ensure_repo "${META_LLAMA_REPO_URL}" "${MODELS_DIR}/Meta-Llama-3-8B-Instruct" "model.safetensors.index.json" "*" || return 1
    ensure_repo_any "${LLM2VEC_PEFT_REPO_URL}" "${MODELS_DIR}/LLM2Vec-Meta-Llama-3-8B-Instruct-mntp-supervised" "adapter_model.safetensors" "model.safetensors" "*" || return 1
  else
    ensure_repo_with_fallback "${LLM2VEC_NF4_REPO_URL}" "${LLM2VEC_NF4_REPO_URL_FALLBACK}" \
      "${MODELS_DIR}/KIMODO-Meta3_llm2vec_NF4" "model.safetensors" "*" || return 1
  fi

  if [[ "${DOWNLOAD_GGUF}" == "1" ]]; then
    echo "[STEP] CPU gguf mode enabled: downloading GGUF text encoder model"
    ensure_repo_with_fallback "${GGUF_REPO_URL}" "${GGUF_REPO_URL_FALLBACK}" \
      "${MODELS_DIR}/Meta-Llama-3.1-8B-Instruct-hf-Q4_K_M-GGUF" ".gguf" "*" || return 1
  fi

  echo "[OK] download_model complete."
  return 0
}

if [[ "${OUTPUT_MODE,,}" == "file" ]]; then
  main > "${LOG_PATH}" 2>&1
  RC=$?
  echo "[INFO] download_model log: ${LOG_PATH}"
  exit "${RC}"
fi
main
exit $?
