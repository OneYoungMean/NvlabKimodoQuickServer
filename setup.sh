#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v cmd.exe >/dev/null 2>&1; then
  exec cmd.exe /d /c "\"${SCRIPT_DIR}\\setup.bat\" $*"
fi

echo "[ERROR] cmd.exe not found. setup.sh is a Windows wrapper and requires cmd.exe." >&2
exit 1
