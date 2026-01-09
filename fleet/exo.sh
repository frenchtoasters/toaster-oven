#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_FILE="${HOSTS_FILE:-${SCRIPT_DIR}/../hosts.txt}"

# Remote location of toaster-oven on each host
TOASTER_OVEN_DIR="${TOASTER_OVEN_DIR:-\$HOME/toaster-oven}"
# Repo URL (public)
TOASTER_OVEN_REPO="${TOASTER_OVEN_REPO:-https://github.com/frenchtoasters/toaster-oven}"

usage() {
  cat <<USAGE
Usage: fleet/exo.sh [--hosts hosts.txt] <cmd> [args]

Core:
  update-all         Full end-to-end update on each host:
                     (clone/pull toaster-oven) -> darwin-rebuild -> exo-bootstrap
                     -> exo-gpu-wired-mem -> exo-repo-sync -> exo-process restart
  repo-update        Ensure toaster-oven is cloned + git pull --rebase on each host
  rebuild            darwin-rebuild switch --flake <remote_repo>#<label> on each host
  bootstrap          Run exo-bootstrap on each host
  gpu-mem            Run exo-gpu-wired-mem on each host
  sync               Run exo-repo-sync on each host
  restart            exo-process stop + start on each host
  start|stop|status  exo-process <cmd> on each host
  tail               Tail exo stdout log

Repo switching helpers (passed to exo-repo-sync):
  branch <name>      Checkout/update a branch (EXO_REPO_BRANCH)
  pr <num>           Checkout/update a PR head (EXO_REPO_PR)
  ref <git-ref>      Checkout/update an arbitrary ref (EXO_REPO_REF)

Env overrides:
  HOSTS_FILE=...          Path to hosts file
  TOASTER_OVEN_DIR=...    Remote dir (default: ~/toaster-oven)
  TOASTER_OVEN_REPO=...   Remote git URL

Examples:
  fleet/exo.sh update-all
  fleet/exo.sh pr 123 && fleet/exo.sh restart
USAGE
}

HOSTS=""
if [[ "${1:-}" == "--hosts" ]]; then
  HOSTS="$2"; shift 2
else
  HOSTS="$HOSTS_FILE"
fi

cmd="${1:-}"; shift || true
[[ -n "$cmd" ]] || { usage; exit 2; }

read_hosts() {
  # format: <label> <ssh_target>
  grep -vE '^\s*(#|$)' "$HOSTS" | awk '{print $1" " $2}'
}

run_on_host() {
  local label="$1" target="$2"; shift 2
  echo "==> ${label} (${target})"
  # Use sh -lc so ~ expands and shell init works for PATH
  ssh -tt -o BatchMode=yes -o ConnectTimeout=5 "$target" "sh -lc $(printf '%q' "$*")" </dev/null
}

repo_update_one() {
  local label="$1" target="$2"
  run_on_host "$label" "$target" "
    set -euo pipefail
    dir=\"$TOASTER_OVEN_DIR\"
    if [ ! -d \"\$dir/.git\" ]; then
      echo \"Cloning toaster-oven into \$dir\"
      git clone \"$TOASTER_OVEN_REPO\" \"\$dir\"
    fi
    cd \"\$dir\"
    git fetch --all --prune
    git pull --rebase
  "
}

rebuild_one() {
  local label="$1" target="$2"
  run_on_host "$label" "$target" "
    set -euo pipefail
    dir=\"$TOASTER_OVEN_DIR\"
    cd \"\$dir\"
    sudo darwin-rebuild switch --flake \"\$dir#$label\"
  "
}

restart_one() {
  local label="$1" target="$2"
  run_on_host "$label" "$target" "
    set -euo pipefail
    exo-process stop || true
    exo-process start
  "
}

case "$cmd" in
  update-all)
    read_hosts | while read -r label target; do
      repo_update_one "$label" "$target"
      rebuild_one "$label" "$target"
      run_on_host "$label" "$target" "exo-bootstrap"
      run_on_host "$label" "$target" "exo-gpu-wired-mem"
      run_on_host "$label" "$target" "exo-repo-sync"
      restart_one "$label" "$target"
    done
    ;;

  repo-update)
    read_hosts | while read -r label target; do
      repo_update_one "$label" "$target"
    done
    ;;

  rebuild)
    read_hosts | while read -r label target; do
      rebuild_one "$label" "$target"
    done
    ;;

  bootstrap)
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "exo-bootstrap"
    done
    ;;

  gpu-mem)
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "exo-gpu-wired-mem"
    done
    ;;

  sync)
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "exo-repo-sync"
    done
    ;;

  restart)
    read_hosts | while read -r label target; do
      restart_one "$label" "$target"
    done
    ;;

  branch)
    b="${1:?branch name required}"
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "EXO_REPO_BRANCH='$b' EXO_REPO_REF='' EXO_REPO_PR='' exo-repo-sync"
    done
    ;;

  pr)
    pr="${1:?PR number required}"
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "EXO_REPO_PR='$pr' EXO_REPO_REF='' exo-repo-sync"
    done
    ;;

  ref)
    ref="${1:?ref required}"
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "EXO_REPO_REF='$ref' EXO_REPO_PR='' exo-repo-sync"
    done
    ;;

  start|stop|status)
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "exo-process $cmd"
    done
    ;;

  tail)
    read_hosts | while read -r label target; do
      run_on_host "$label" "$target" "tail -n 200 -f ~/.exo-fleet/logs/exo.out.log"
    done
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 2
    ;;
esac
