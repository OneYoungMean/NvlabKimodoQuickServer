#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="${SCRIPT_DIR}"

resolve_uv_bin() {
  if [[ -n "${KIMODO_UV_BIN:-}" ]]; then
    echo "${KIMODO_UV_BIN}"
  elif [[ -x "${ROOT_DIR}/program/exe/uv/uv" ]]; then
    echo "${ROOT_DIR}/program/exe/uv/uv"
  elif [[ -x "${ROOT_DIR}/program/exe/uv/uv.exe" ]]; then
    echo "${ROOT_DIR}/program/exe/uv/uv.exe"
  elif command -v uv >/dev/null 2>&1; then
    command -v uv
  else
    echo ""
  fi
}

run_as_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_uv_best_effort() {
  if command -v brew >/dev/null 2>&1; then
    brew install uv
    return
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    return
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
    return
  fi
  echo "[ERROR] Could not auto-install uv: curl or wget is required."
  return 1
}

prompt_install_missing_tools() {
  local missing=("$@")
  local answer=""
  echo "[ERROR] Missing required command-line tool(s): ${missing[*]}"
  read -r -p "Would you like Kimodo QuickServer to try installing them now? [Y/N] " answer
  case "${answer}" in
    Y|y|Yes|YES|yes)
      for tool in "${missing[@]}"; do
        case "${tool}" in
          uv)
            install_uv_best_effort || return 1
            export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
            ;;
        esac
      done
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

UV_BIN="$(resolve_uv_bin)"

if [[ -n "${KIMODO_TEST_VENV_PATH:-}" ]]; then
  echo "[ERROR] KIMODO_TEST_VENV_PATH has been removed. Use KIMODO_VENV_PATH."
  exit 1
fi
if [[ -n "${KIMODO_TEST_SETUP_DEVICE:-}" ]]; then
  echo "[ERROR] KIMODO_TEST_SETUP_DEVICE has been removed. Use KIMODO_SETUP_DEVICE."
  exit 1
fi
if [[ -n "${KIMODO_CPU_TEXT_ENCODER:-}" ]]; then
  echo "[ERROR] KIMODO_CPU_TEXT_ENCODER has been removed. QuickServer now auto-selects the local INT8 text encoder route."
  exit 1
fi
if [[ -n "${CHECKPOINT_DIR:-}" ]]; then
  echo "[ERROR] CHECKPOINT_DIR has been removed. Use KIMODO_MODELS_ROOT."
  exit 1
fi

MISSING_TOOLS=()
if [[ -z "${UV_BIN}" || ! -x "${UV_BIN}" ]]; then
  MISSING_TOOLS+=("uv")
fi

if [[ "${#MISSING_TOOLS[@]}" -gt 0 ]]; then
  prompt_install_missing_tools "${MISSING_TOOLS[@]}" || exit 1
  UV_BIN="$(resolve_uv_bin)"
fi

if [[ -z "${UV_BIN}" || ! -x "${UV_BIN}" ]]; then
  echo "[ERROR] uv is still unavailable after installation attempt."
  exit 1
fi

ARGS=("$@")
HAS_VENV_ARG=0
for arg in "${ARGS[@]}"; do
  if [[ "${arg}" == "--venv" ]]; then
    HAS_VENV_ARG=1
    break
  fi
done
if [[ -n "${KIMODO_VENV_PATH:-}" && "${HAS_VENV_ARG}" -eq 0 ]]; then
  ARGS+=("--venv" "${KIMODO_VENV_PATH}")
fi

exec "${UV_BIN}" run --python 3.12 --no-project python "${ROOT_DIR}/quickserver.py" "${ARGS[@]}"
