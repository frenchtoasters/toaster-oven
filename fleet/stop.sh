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
  mapfile -t HOST_ENTRIES < <(read_hosts "$HOSTS")

  for entry in "${HOST_ENTRIES[@]}"; do
    read -r _ ssh_target <<<"$entry"
    [[ -n "$ssh_target" ]] || continue

    log "$ssh_target: stopping EXO"
    scp_to "$SCRIPT_DIR/lib/exo_process.sh" "$ssh_target" "/tmp/exo_process.sh"

    ssh_run_tty "$ssh_target" "sh -lc '
      set -euo pipefail
      sudo -v
      chmod +x /tmp/exo_process.sh
      /tmp/exo_process.sh stop
    '"
  done
}

main
