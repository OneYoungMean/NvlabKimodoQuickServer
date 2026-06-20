#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"
UV_BIN="${ROOT_DIR}/program/exe/uv/uv.exe"

if [[ ! -x "${UV_BIN}" ]]; then
  echo "[ERROR] Missing bundled uv: ${UV_BIN}"
  exit 1
fi

forward_args=(prepare-models)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unlock-stale)
      shift
      ;;
    *)
      forward_args+=("$1")
      shift
      ;;
  esac
done

exec "${UV_BIN}" run --python 3.12 --no-project python "${ROOT_DIR}/quickserver.py" "${forward_args[@]}"
