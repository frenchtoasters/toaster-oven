#!/usr/bin/env bash
set -euo pipefail

EXO_DIR="/opt/exo"
PIDFILE="$EXO_DIR/.exo.pid"
LOGDIR="$EXO_DIR/.exo-logs"
STDOUT_LOG="$LOGDIR/exo.out.log"
STDERR_LOG="$LOGDIR/exo.err.log"

ensure_dirs() { mkdir -p "$LOGDIR"; }

is_running() {
  if [[ -f "$PIDFILE" ]]; then
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
  else
    return 1
  fi
}

stop_process() {
  if is_running; then
    local pid
    pid="$(cat "$PIDFILE")"
    echo "Stopping EXO pid=$pid"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      sleep 1
      if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$PIDFILE"
        echo "Stopped."
        return 0
      fi
    done
    echo "Force killing EXO pid=$pid"
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
  else
    echo "No running EXO process (pidfile missing or dead)."
    rm -f "$PIDFILE" 2>/dev/null || true
  fi
}

start_process() {
  ensure_dirs
  stop_process

  # Debug header
  {
    echo "==== $(date) ===="
    echo "Starting EXO from $EXO_DIR"
    echo "User: $(id -un)"
    echo "PWD before cd: $(pwd)"
  } >>"$STDOUT_LOG"

  cd "$EXO_DIR"

  # Load nix profile for non-interactive shells
  if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
  fi

  {
    echo "PATH=$PATH"
    command -v nix || echo "nix not found on PATH"
    command -v uv  || echo "uv not found on PATH (ok if provided by nix develop)"
  } >>"$STDOUT_LOG"

  # Run via a dedicated wrapper script so we can capture the exit code
  local runner="$EXO_DIR/.exo-runner.sh"
  cat >"$runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/exo/dashboard && npm install && npm run build
cd /opt/exo
exec nix develop --command uv run exo
EOF
  chmod +x "$runner"

  echo "Launching: $runner" >>"$STDOUT_LOG"

  # Start in background; capture logs
  nohup "$runner" >>"$STDOUT_LOG" 2>>"$STDERR_LOG" &
  echo $! > "$PIDFILE"
  echo "Started pid=$(cat "$PIDFILE")" >>"$STDOUT_LOG"
}

status() {
  if is_running; then
    local pid
    pid="$(cat "$PIDFILE")"
    echo "EXO is running pid=$pid"
    ps -fp "$pid" || true
    exit 0
  else
    echo "EXO is NOT running"
    if [[ -f "$PIDFILE" ]]; then
      echo "PID file exists but process is dead: $(cat "$PIDFILE" 2>/dev/null || true)"
    fi
    exit 1
  fi
}

usage() {
  cat <<EOF
Usage: $0 <command>

Commands:
  start   Stop any existing EXO process, then start a new one
  stop    Stop existing EXO process
  status  Show status
EOF
}

cmd="${1:-}"
case "$cmd" in
  start)   start_process ;;
  stop)    stop_process ;;
  status)  status ;;
  ""|-h|--help) usage ;;
  *) echo "Unknown command: $cmd" >&2; usage; exit 2 ;;
esac
