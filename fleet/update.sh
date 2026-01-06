#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
update.sh
- macOS: kickstart org.nixos.exo-repo-sync (launchd)
- linux: run exo-repo-sync command (installed by Home Manager) with env overrides

Usage:
  ./fleet/update.sh --hosts hosts.txt --branch <branch>

Optional:
  --repo-https https://github.com/exo-explore/exo-v2.git   (default)
  --dest /opt/exo                                         (default)
EOF
}

HOSTS=""
BRANCH=""
REPO_HTTPS="https://github.com/exo-explore/exo-v2.git"
DEST="/opt/exo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2;;
    --branch) BRANCH="$2"; shift 2;;
    --repo-https) REPO_HTTPS="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

[[ -n "$HOSTS" ]] || die "--hosts is required"
[[ -n "$BRANCH" ]] || die "--branch is required"

update_macos() {
  local target="$1"
  log "$target: updating via launchd org.nixos.exo-repo-sync (SIP-safe)"
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail
    sudo -v

    # Don’t use launchctl setenv (blocked by SIP).
    # Just run the nix-darwin-managed job.
    sudo /bin/launchctl kickstart -k system/org.nixos.exo-repo-sync || true
    sudo /bin/launchctl start system/org.nixos.exo-repo-sync || true
  '"
}

update_linux() {
  local target="$1"
  log "$target: updating via exo-repo-sync (branch=$BRANCH)"
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail
    $remote_nix_profile_snippet

    sudo -v
    sudo mkdir -p \"$DEST\"
    sudo chown \"$ssh_user\" \"$DEST\" || true

    EXO_REPO_BRANCH=\"$BRANCH\" EXO_REPO_URL_HTTPS=\"$REPO_HTTPS\" EXO_REPO_DEST=\"$DEST\" \
      exo-repo-sync
  '"
}

main() {
  mapfile -t HOST_ENTRIES < <(read_hosts "$HOSTS")

  for entry in "${HOST_ENTRIES[@]}"; do
    read -r _ ssh_target <<<"$entry"
    [[ -n "$ssh_target" ]] || continue

    if remote_is_darwin "$ssh_target"; then
      update_macos "$ssh_target"
    else
      update_linux "$ssh_target"
    fi

    log "$ssh_target: update complete"
  done
}

main
