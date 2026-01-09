#!/usr/bin/env bash
set -euo pipefail

EXO_DIR="${EXO_DIR:-/opt/exo}"
STATE_DIR="${STATE_DIR:-${HOME}/.exo-fleet}"
PIDFILE="${PIDFILE:-${STATE_DIR}/exo.pid}"
LOGDIR="${LOGDIR:-${STATE_DIR}/logs}"
STDOUT_LOG="${STDOUT_LOG:-${LOGDIR}/exo.out.log}"
STDERR_LOG="${STDERR_LOG:-${LOGDIR}/exo.err.log}"

# Optional override (e.g. EXO_RUN_CMD='uv run exo --help')
EXO_RUN_CMD="${EXO_RUN_CMD:-uv run exo}"

ensure_dirs() { mkdir -p "${LOGDIR}"; }

_is_running_pid() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

is_running() {
  [[ -f "${PIDFILE}" ]] || return 1
  local pid
  pid="$(cat "${PIDFILE}" 2>/dev/null || true)"
  _is_running_pid "${pid}"
}

stop_process() {
  if is_running; then
    local pid
    pid="$(cat "${PIDFILE}")"
    echo "Stopping EXO pid=${pid}"
    kill "${pid}" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      sleep 1
      if ! _is_running_pid "${pid}"; then
        rm -f "${PIDFILE}"
        echo "Stopped."
        return 0
      fi
    done
    echo "Force killing EXO pid=${pid}"
    kill -9 "${pid}" 2>/dev/null || true
    rm -f "${PIDFILE}"
  else
    echo "No running EXO process (pidfile missing or dead)."
    rm -f "${PIDFILE}" 2>/dev/null || true
  fi
}

_start_env_path() {
  # Make sure Homebrew + user tools are visible for launchd/ssh non-interactive shells
  local p="${PATH}"
  for d in "/opt/homebrew/bin" "/opt/homebrew/sbin" "/usr/local/bin" "/usr/local/sbin" "${HOME}/.cargo/bin"; do
    if [[ -d "${d}" ]]; then
      p="${d}:${p}"
    fi
  done
  echo "${p}"
}

start_process() {
  ensure_dirs
  stop_process

  {
    echo "==== $(date) ===="
    echo "Starting EXO from ${EXO_DIR}"
    echo "User: $(id -un)"
    echo "HOME: ${HOME}"
    echo "PWD before cd: $(pwd)"
  } >>"${STDOUT_LOG}"

  if [[ ! -d "${EXO_DIR}" ]]; then
    echo "ERROR: EXO_DIR does not exist: ${EXO_DIR}" >>"${STDERR_LOG}"
    echo "Hint: run exo-repo-sync first (or check EXO_DIR)" >>"${STDERR_LOG}"
    exit 1
  fi

  PATH="$(_start_env_path)" || exit
  export PATH

  {
    echo "PATH=${PATH}"
    command -v uv  || echo "uv not found on PATH"
    command -v npm || echo "npm not found on PATH"
  } >>"${STDOUT_LOG}"

  local runner
  runner="${STATE_DIR}/exo-runner.sh"
  cat >"${runner}" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

EXO_DIR="${EXO_DIR:-/opt/exo}"
EXO_RUN_CMD="${EXO_RUN_CMD:-uv run exo}"

# Same PATH logic here because launchd + nohup can lose env
p="${PATH}"
for d in "/opt/homebrew/bin" "/opt/homebrew/sbin" "/usr/local/bin" "/usr/local/sbin" "${HOME}/.cargo/bin"; do
  if [[ -d "${d}" ]]; then
    p="${d}:${p}"
  fi
done
export PATH="$p"

cd "${EXO_DIR}/dashboard"
# Keeping this explicit per your workflow (build on every start)
npm install
npm run build

cd "${EXO_DIR}"
exec ${EXO_RUN_CMD}
EOS
  chmod +x "${runner}"

  echo "Launching: ${runner}" >>"${STDOUT_LOG}"
  nohup "${runner}" >>"${STDOUT_LOG}" 2>>"${STDERR_LOG}" &
  echo $! >"${PIDFILE}"
  echo "Started pid=$(cat "${PIDFILE}")"
}

status() {
  if is_running; then
    local pid
    pid="$(cat "${PIDFILE}")"
    echo "EXO is running pid=${pid}"
    ps -p "${pid}" -o pid,ppid,user,etime,command || true
    exit 0
  else
    echo "EXO is NOT running"
    if [[ -f "${PIDFILE}" ]]; then
      echo "PID file exists but process is dead: $(cat "${PIDFILE}" 2>/dev/null || true)"
    fi
    exit 1
  fi
}

cmd="${1:-}"
case "${cmd}" in
  start)  start_process ;;
  stop)   stop_process ;;
  status) status ;;
  ""|-h|--help)
    echo "Usage: exo-process {start|stop|status}"
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    echo "Usage: exo-process {start|stop|status}" >&2
    exit 2
    ;;
esac
