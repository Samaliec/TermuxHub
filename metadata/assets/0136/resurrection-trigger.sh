#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APP_ID="gembot-yal-lilith"
BASE_DIR="${HOME}/.local/share/${APP_ID}"
BIN_DIR="${BASE_DIR}/bin"
STATE_DIR="${BASE_DIR}/state"
LOG_DIR="${BASE_DIR}/logs"
LAST_GOOD_DIR="${BASE_DIR}/last-known-good"
CONFIG_FILE="${HOME}/.config/${APP_ID}/trigger.env"
LOCK_DIR="${BASE_DIR}/lock"
CRON_FILE="${HOME}/.termux/cron/${APP_ID}"
LOG_FILE="${LOG_DIR}/resurrection.log"
PID_FILE="${STATE_DIR}/assistant.pid"
QUIET_HOURS_START="00:30"
QUIET_HOURS_END="06:30"
ALLOWED_LOCAL_CIDRS="127.0.0.1/32,192.168.0.0/16,10.0.0.0/8"
HEARTBEAT_NAME="Fractal Node v6"
ASSISTANT_CMD=(python "${BIN_DIR}/assistant_stub.py")
SELF_TEST_CMD=(python "${BIN_DIR}/assistant_stub.py" --self-test)
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

log() {
  mkdir -p "${LOG_DIR}"
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "${LOG_FILE}"
}

load_config() {
  if [[ -f "${CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_FILE}"
  fi
}

ensure_layout() {
  mkdir -p "${BIN_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${LAST_GOOD_DIR}" "$(dirname "${CONFIG_FILE}")" "$(dirname "${CRON_FILE}")"
}

write_default_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    cat > "${CONFIG_FILE}" <<CFG
QUIET_HOURS_START="${QUIET_HOURS_START}"
QUIET_HOURS_END="${QUIET_HOURS_END}"
ALLOWED_LOCAL_CIDRS="${ALLOWED_LOCAL_CIDRS}"
HEARTBEAT_NAME="${HEARTBEAT_NAME}"
ASSISTANT_CMD=(python "${BIN_DIR}/assistant_stub.py")
SELF_TEST_CMD=(python "${BIN_DIR}/assistant_stub.py" --self-test)
CFG
  fi
}

backup_known_good() {
  cp -f "$0" "${LAST_GOOD_DIR}/resurrection-trigger.sh"
  if [[ -f "${BIN_DIR}/assistant_stub.py" ]]; then
    cp -f "${BIN_DIR}/assistant_stub.py" "${LAST_GOOD_DIR}/assistant_stub.py"
  fi
}

to_minutes() {
  local hh mm
  hh="${1%%:*}"
  mm="${1##*:}"
  printf '%d' "$((10#${hh} * 60 + 10#${mm}))"
}

within_quiet_hours() {
  local now start end
  now="$(date '+%H:%M')"
  start="$(to_minutes "${QUIET_HOURS_START}")"
  end="$(to_minutes "${QUIET_HOURS_END}")"
  now="$(to_minutes "${now}")"

  if (( start == end )); then
    return 1
  fi

  if (( start < end )); then
    (( now >= start && now < end ))
  else
    (( now >= start || now < end ))
  fi
}

ensure_dependencies() {
  local missing=0
  for cmd in bash python pkill pgrep nohup; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      log "missing dependency: ${cmd}"
      missing=1
    fi
  done
  return "${missing}"
}

restore_known_good() {
  local restored=1
  if [[ -f "${LAST_GOOD_DIR}/assistant_stub.py" ]]; then
    cp -f "${LAST_GOOD_DIR}/assistant_stub.py" "${BIN_DIR}/assistant_stub.py"
    restored=0
    log "assistant restored from last-known-good"
  fi
  if [[ -f "${LAST_GOOD_DIR}/resurrection-trigger.sh" ]]; then
    cp -f "${LAST_GOOD_DIR}/resurrection-trigger.sh" "$0"
    chmod +x "$0"
    restored=0
    log "trigger refreshed from last-known-good"
  fi
  return "${restored}"
}

validate_runtime() {
  [[ -f "${BIN_DIR}/assistant_stub.py" ]] || return 1
  python -m py_compile "${BIN_DIR}/assistant_stub.py" >/dev/null 2>&1
}

run_self_test() {
  export GEMBOT_ALLOWED_LOCAL_CIDRS="${ALLOWED_LOCAL_CIDRS}"
  export GEMBOT_HEARTBEAT_NAME="${HEARTBEAT_NAME}"
  export GEMBOT_STATE_DIR="${STATE_DIR}"
  "${SELF_TEST_CMD[@]}"
}

assistant_running() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

start_assistant() {
  export GEMBOT_ALLOWED_LOCAL_CIDRS="${ALLOWED_LOCAL_CIDRS}"
  export GEMBOT_HEARTBEAT_NAME="${HEARTBEAT_NAME}"
  export GEMBOT_STATE_DIR="${STATE_DIR}"

  nohup "${ASSISTANT_CMD[@]}" >> "${LOG_DIR}/assistant.stdout.log" 2>> "${LOG_DIR}/assistant.stderr.log" &
  local pid=$!
  printf '%s\n' "${pid}" > "${PID_FILE}"
  log "assistant started with pid ${pid}"
}

stop_assistant() {
  if assistant_running; then
    local pid
    pid="$(cat "${PID_FILE}")"
    kill "${pid}" >/dev/null 2>&1 || true
    rm -f "${PID_FILE}"
    log "assistant stopped"
  else
    log "assistant already stopped"
  fi
}

install_cron() {
  cat > "${CRON_FILE}" <<CRON
*/5 * * * * bash ${BIN_DIR}/resurrection-trigger.sh --cycle
CRON
  log "cron entry written to ${CRON_FILE}"
}

install_mode() {
  ensure_layout
  write_default_config
  if [[ -f "$0" && "$0" != "${BIN_DIR}/resurrection-trigger.sh" ]]; then
    cp -f "$0" "${BIN_DIR}/resurrection-trigger.sh"
    chmod +x "${BIN_DIR}/resurrection-trigger.sh"
  fi
  if [[ -f "${SOURCE_DIR}/assistant_stub.py" && ! -f "${BIN_DIR}/assistant_stub.py" ]]; then
    cp -f "${SOURCE_DIR}/assistant_stub.py" "${BIN_DIR}/assistant_stub.py"
    chmod +x "${BIN_DIR}/assistant_stub.py"
  fi
  backup_known_good
  install_cron
  log "installation complete; start crond and run the trigger once"
}

status_mode() {
  ensure_layout
  load_config
  if assistant_running; then
    log "status: running pid=$(cat "${PID_FILE}")"
  else
    log "status: stopped"
  fi
  if within_quiet_hours; then
    log "quiet-hours: active (${QUIET_HOURS_START}-${QUIET_HOURS_END})"
  else
    log "quiet-hours: inactive"
  fi
}

cycle_mode() {
  ensure_layout
  load_config

  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    log "cycle skipped: another cycle is running"
    exit 0
  fi
  trap 'rmdir "${LOCK_DIR}"' EXIT

  if ! ensure_dependencies; then
    log "dependency check failed"
    exit 1
  fi

  if within_quiet_hours; then
    log "quiet hours active; only health checks are allowed"
    if ! validate_runtime; then
      restore_known_good || true
    fi
    run_self_test
    exit 0
  fi

  if ! validate_runtime; then
    log "runtime validation failed; attempting restoration"
    restore_known_good || true
  fi

  if ! run_self_test; then
    log "self-test failed; attempting restoration"
    restore_known_good || true
    run_self_test
  fi

  if assistant_running; then
    log "assistant already running"
  else
    start_assistant
  fi

  backup_known_good
}

case "${1:---cycle}" in
  --install)
    install_mode
    ;;
  --cycle)
    cycle_mode
    ;;
  --status)
    status_mode
    ;;
  --stop)
    stop_assistant
    ;;
  *)
    echo "Usage: $0 [--install|--cycle|--status|--stop]" >&2
    exit 1
    ;;
esac
