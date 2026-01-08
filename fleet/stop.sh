#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

HOSTS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2;;
    -h|--help) echo "Usage: ./fleet/stop.sh --hosts hosts.txt"; exit 0;;
    *) die "unknown arg: $1";;
  esac
done
[[ -n "$HOSTS" ]] || die "--hosts is required"

main() {
  read_hosts "$HOSTS" | while read -r _ ssh_target; do
    log "$ssh_target: restarting EXO"

    ssh_run_tty "$ssh_target" "sh -lc '
      set -euo pipefail
      export PATH=\"$HOME/.nix-profile/bin:/etc/profiles/per-user/\$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:\$PATH\"

      if command -v exo-process >/dev/null 2>&1; then
        exo-process stop
      else
        echo \"exo-process not found on PATH; nothing to stop\" >&2
      fi
    '"
  done
}

main
