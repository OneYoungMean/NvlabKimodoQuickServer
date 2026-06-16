#!/usr/bin/env bash
# Linux equivalent of common_env.bat. Sourced as a function library by the other
# Linux scripts. The .bat dispatches subroutines via "call common_env.bat :name";
# here the caller sources this file and calls the bash functions directly.
#
# Process-identity checks use /proc/<pid>/cmdline (Linux) instead of the .bat's
# Win32_Process CIM query. A bridge process is identified by a python interpreter
# whose command line contains both "kimodo.bridge.bridge_server" and "--kimodo-root".

# Resolve a venv directory or python path into an absolute python executable.
# Prints the resolved path on stdout; returns non-zero on failure.
common_resolve_venv_python() {
  local venv_input="${1:-}"
  if [[ -z "${venv_input}" ]]; then
    echo "[ERROR] --venv requires a path." >&2
    return 1
  fi
  local cand="${venv_input}"
  if [[ "${cand}" == *"/python" || "${cand}" == *"/python3" ]]; then
    : # already a python executable path
  elif [[ "${cand}" == */bin ]]; then
    cand="${cand}/python"
  else
    cand="${cand}/bin/python"
  fi
  if [[ ! -x "${cand}" ]]; then
    echo "[ERROR] Invalid --venv path, python not found: ${cand}" >&2
    return 1
  fi
  # Emit absolute path.
  ( cd "$(dirname "${cand}")" >/dev/null 2>&1 && echo "$(pwd)/$(basename "${cand}")" )
  return 0
}

# Archive (move aside) a file or directory into the recycle dir with a timestamp.
# Mirrors :archive_file. Never fails the caller: a missing target is a no-op.
common_archive_file() {
  local target="${1:-}"
  local recycle_dir="${2:-}"
  [[ -z "${target}" ]] && return 0
  [[ ! -e "${target}" ]] && return 0
  if [[ -z "${recycle_dir}" ]]; then
    if [[ -n "${ROOT_DIR:-}" ]]; then
      recycle_dir="${ROOT_DIR}/archive/recycle"
    else
      recycle_dir="$(dirname "${BASH_SOURCE[0]}")/../archive/recycle"
    fi
  fi
  mkdir -p "${recycle_dir}" >/dev/null 2>&1 || true
  local ts base dest
  ts="$(date +%Y%m%d_%H%M%S)"
  base="$(basename "${target}")"
  dest="${recycle_dir}/${base}.${ts}.${RANDOM}"
  mv "${target}" "${dest}" >/dev/null 2>&1 || true
  return 0
}

# Return 0 if pid is a live kimodo bridge process, non-zero otherwise.
common_is_kimodo_bridge_pid() {
  local check_pid="${1:-}"
  [[ -z "${check_pid}" ]] && return 1
  [[ ! -d "/proc/${check_pid}" ]] && return 1
  local cmdline
  # cmdline is NUL-separated; translate to spaces for matching.
  cmdline="$(tr '\0' ' ' < "/proc/${check_pid}/cmdline" 2>/dev/null || true)"
  [[ -z "${cmdline}" ]] && return 1
  case "${cmdline}" in
    *python*) : ;;
    *) return 2 ;;
  esac
  if [[ "${cmdline}" == *"kimodo.bridge.bridge_server"* && "${cmdline}" == *"--kimodo-root"* ]]; then
    return 0
  fi
  return 3
}

# Kill pid only if it is a kimodo bridge process (TERM, then KILL after grace).
common_kill_pid_if_kimodo_bridge() {
  local kill_pid="${1:-}"
  [[ -z "${kill_pid}" ]] && return 1
  if ! common_is_kimodo_bridge_pid "${kill_pid}"; then
    return 1
  fi
  kill -TERM "${kill_pid}" >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 10); do
    [[ ! -d "/proc/${kill_pid}" ]] && return 0
    sleep 0.3
  done
  kill -KILL "${kill_pid}" >/dev/null 2>&1 || true
  return 0
}
