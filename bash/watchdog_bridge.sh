#!/usr/bin/env bash
# Linux equivalent of watchdog_bridge.bat. Waits for the bridge to publish its
# serverport, then monitors liveness: kills the bridge if serverport never
# appears within max_fails checks, or if the bridge log goes stale at runtime.
#
# Usage: watchdog_bridge.sh <root_dir> <pid> <port_file> <bootstrap_log_path> \
#            <startup_interval_sec> <startup_max_fails> <runtime_interval_sec> <idle_nolog_max>
set -uo pipefail

ROOT_DIR="${1:-}"
WD_PID="${2:-}"
PORT_FILE="${3:-}"
BOOTSTRAP_LOG_PATH="${4:-}"
WATCHDOG_INTERVAL_SEC="${5:-1}"
WATCHDOG_MAX_FAILS="${6:-180}"
WATCHDOG_RUNTIME_INTERVAL_SEC="${7:-1}"
WATCHDOG_IDLE_NOLOG_MAX="${8:-300}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_env.sh"

WD_LOG_PATH="${ROOT_DIR}/log/bridge_message.log"
WATCHDOG_LOG_PATH="${ROOT_DIR}/log/watchdog.log"
mkdir -p "${ROOT_DIR}/log" >/dev/null 2>&1 || true

[[ "${WATCHDOG_INTERVAL_SEC}" -le 0 ]] 2>/dev/null && WATCHDOG_INTERVAL_SEC=1
[[ "${WATCHDOG_RUNTIME_INTERVAL_SEC}" -le 0 ]] 2>/dev/null && WATCHDOG_RUNTIME_INTERVAL_SEC=1

log() {
  echo "$*"
  echo "$*" >> "${WATCHDOG_LOG_PATH}"
}

is_pid_running() {
  local p="${1:-}"
  [[ -z "${p}" ]] && return 1
  [[ -d "/proc/${p}" ]] && return 0
  return 1
}

file_mtime_epoch() {
  local f="$1"
  [[ -f "${f}" ]] || { echo ""; return 0; }
  stat -c %Y "${f}" 2>/dev/null || echo ""
}

log "[INFO] Bridge watchdog started. pid=${WD_PID} startup_interval=${WATCHDOG_INTERVAL_SEC}s startup_max_fails=${WATCHDOG_MAX_FAILS} runtime_interval=${WATCHDOG_RUNTIME_INTERVAL_SEC}s idle_nolog_max=${WATCHDOG_IDLE_NOLOG_MAX}"

WD_FAILS=0
WATCHDOG_STARTED_OK=0
WD_LOG_STALE=0
WD_LOG_LAST=""

while true; do
  if ! is_pid_running "${WD_PID}"; then
    if [[ "${WATCHDOG_STARTED_OK}" == "1" ]]; then
      log "[INFO] Bridge process/thread invalid. pid=${WD_PID}"
      exit 0
    else
      log "[ERROR] Bridge process/thread invalid before serverport appeared. pid=${WD_PID}"
      exit 1
    fi
  fi

  if [[ "${WATCHDOG_STARTED_OK}" != "1" ]]; then
    # startup phase: wait for serverport
    if [[ -f "${PORT_FILE}" ]]; then
      log "[INFO] serverport detected: ${PORT_FILE}"
      WATCHDOG_STARTED_OK=1
      WD_LOG_LAST="$(file_mtime_epoch "${WD_LOG_PATH}")"
      [[ -z "${WD_LOG_LAST}" ]] && WD_LOG_LAST=0
      WD_LOG_STALE=0
      sleep "${WATCHDOG_RUNTIME_INTERVAL_SEC}"
      continue
    fi
    WD_FAILS=$((WD_FAILS + 1))
    log "[INFO] Waiting serverport (${WD_FAILS}/${WATCHDOG_MAX_FAILS})"
    if [[ "${WD_FAILS}" -ge "${WATCHDOG_MAX_FAILS}" ]]; then
      log "[ERROR] serverport not found within ${WATCHDOG_MAX_FAILS} checks. Killing pid=${WD_PID}"
      common_kill_pid_if_kimodo_bridge "${WD_PID}" || { log "[ERROR] Failed to kill bridge pid=${WD_PID}"; exit 1; }
      exit 1
    fi
    sleep "${WATCHDOG_INTERVAL_SEC}"
    continue
  fi

  # runtime phase: detect stale bridge log
  WD_LOG_NOW="$(file_mtime_epoch "${WD_LOG_PATH}")"
  [[ -z "${WD_LOG_NOW}" ]] && WD_LOG_NOW="${WD_LOG_LAST}"
  if [[ "${WD_LOG_NOW}" == "${WD_LOG_LAST}" ]]; then
    WD_LOG_STALE=$((WD_LOG_STALE + 1))
  else
    WD_LOG_STALE=0
    WD_LOG_LAST="${WD_LOG_NOW}"
  fi
  if [[ "${WD_LOG_STALE}" -ge "${WATCHDOG_IDLE_NOLOG_MAX}" ]]; then
    log "[INFO] No bridge log update for ${WATCHDOG_IDLE_NOLOG_MAX} checks. Killing pid=${WD_PID}"
    common_kill_pid_if_kimodo_bridge "${WD_PID}" || { log "[ERROR] Failed to kill bridge pid=${WD_PID}"; exit 1; }
    exit 0
  fi
  sleep "${WATCHDOG_RUNTIME_INTERVAL_SEC}"
done
