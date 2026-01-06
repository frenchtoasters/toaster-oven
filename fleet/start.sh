#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

HOSTS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2;;
    -h|--help) echo "Usage: ./fleet/start.sh --hosts hosts.txt"; exit 0;;
    *) die "unknown arg: $1";;
  esac
done
[[ -n "$HOSTS" ]] || die "--hosts is required"

main() {
  mapfile -t HOST_ENTRIES < <(read_hosts "$HOSTS")

  for entry in "${HOST_ENTRIES[@]}"; do
    read -r ssh_user ssh_target <<<"$entry"
    [[ -n "$ssh_user" && -n "$ssh_target" ]] || continue

    log "$ssh_target: restarting EXO"
    scp_to "$SCRIPT_DIR/lib/exo_process.sh" "$ssh_target" "/tmp/exo_process.sh"

    ssh_run_tty "$ssh_target" "sh -lc '
      set -euo pipefail
      sudo -v
      sudo mkdir -p /opt/exo || true

      # chown to the configured user (from hosts.txt / darwinConfiguration key)
      sudo chown \"$ssh_user\" /opt/exo || true

      chmod +x /tmp/exo_process.sh
      /tmp/exo_process.sh start
    '"
  done
}

main
