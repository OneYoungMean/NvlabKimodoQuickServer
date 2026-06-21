#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="${SCRIPT_DIR}"
UV_BIN="${ROOT_DIR}/program/exe/uv/uv.exe"

if [[ ! -x "${UV_BIN}" ]]; then
  echo "[ERROR] Missing bundled uv: ${UV_BIN}"
  exit 1
fi

exec "${UV_BIN}" run --python 3.12 --no-project python "${ROOT_DIR}/quickserver.py" "$@"
