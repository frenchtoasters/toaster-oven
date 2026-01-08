#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
bootstrap.sh
  - installs your SSH pubkey on all hosts
  - installs Nix (daemon / multi-user)
  - enforces flakes + nix-command in /etc/nix/nix.conf
  - applies flake:
      macOS via nix-darwin
      Linux via home-manager
  - PAT:
      macOS -> System Keychain (exo-github-pat)
      Linux -> ~/.git-credentials (credential.helper store)
  - Linux: enables linger + enables org.nixos.exo-repo-sync.timer (periodic sync)

Usage:
  GH_PAT=... ./fleet/bootstrap.sh --hosts hosts.txt --pubkey ~/.ssh/id_ed25519.pub --flake-dir .
EOF
}

HOSTS=""
PUBKEY=""
FLAKE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hosts) HOSTS="$2"; shift 2;;
    --pubkey) PUBKEY="$2"; shift 2;;
    --flake-dir) FLAKE_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: $1";;
  esac
done

[[ -n "$HOSTS" ]] || die "--hosts is required"
[[ -n "$PUBKEY" ]] || die "--pubkey is required"
[[ -n "$FLAKE_DIR" ]] || die "--flake-dir is required"
[[ -f "$PUBKEY" ]] || die "pubkey not found: $PUBKEY"
[[ -f "$FLAKE_DIR/flake.nix" ]] || die "flake.nix not found in: $FLAKE_DIR"

: "${GH_PAT:?GH_PAT env var is required for bootstrap}"

PUBKEY_CONTENT="$(cat "$PUBKEY")"

install_pubkey_remote() {
  local target="$1"
  log "$target: installing ssh pubkey"
  ssh_run "$target" "sh -lc 'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; grep -qxF \"$PUBKEY_CONTENT\" ~/.ssh/authorized_keys || echo \"$PUBKEY_CONTENT\" >> ~/.ssh/authorized_keys'"
}

install_nix_and_conf() {
  local target="$1"
  log "$target: installing Nix + enforcing /etc/nix/nix.conf experimental-features"
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail
    if ! command -v nix >/dev/null 2>&1; then
      curl --proto \"=https\" --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
    fi

    if [ ! -f /etc/nix/nix.conf ]; then
      sudo mkdir -p /etc/nix
      sudo touch /etc/nix/nix.conf
    fi
    sudo -v

    if ! sudo grep -q \"^experimental-features\" /etc/nix/nix.conf; then
      echo \"experimental-features = nix-command flakes\" | sudo tee -a /etc/nix/nix.conf >/dev/null
    else
      sudo sed -i.bak -E \"s/^experimental-features.*/experimental-features = nix-command flakes/\" /etc/nix/nix.conf || true
    fi
  '"
}


apply_flake_remote() {
  local target="$1" flake_name="$2"
  log "$target: copying flake repo + applying configuration (#$flake_name)"

  # Use a HOME-relative path that rsync can reliably expand via "~"
  local remote_dir_rel=".cache/exo-fleet/flake"
  local remote_dir_rsync="~/${remote_dir_rel}"

  # Hard reset staging dir. Try without sudo first; if permissions are borked from old runs, fix with sudo.
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail

    if rm -rf \"\$HOME/${remote_dir_rel}\" 2>/dev/null; then
      mkdir -p \"\$HOME/${remote_dir_rel}\"
    else
      sudo -v
      sudo rm -rf \"\$HOME/${remote_dir_rel}\"
      mkdir -p \"\$HOME/${remote_dir_rel}\"
      sudo chown -R \"\$USER\" \"\$HOME/.cache/exo-fleet\" || true
    fi
  '"

  # IMPORTANT: pass a literal "~/" destination so remote shell expands it correctly
  rsync_to "$FLAKE_DIR/" "$target" "$remote_dir_rsync/"

  if remote_is_darwin "$target"; then
    ssh_run_tty "$target" "sh -lc '
      set -euo pipefail
      $remote_nix_profile_snippet
      cd \"\$HOME/${remote_dir_rel}\"

      sudo -v
      sudo nix run github:LnL7/nix-darwin -- switch --flake .#$flake_name
    '"
  else
    ssh_run_tty "$target" "sh -lc '
      set -euo pipefail
      $remote_nix_profile_snippet
      cd \"\$HOME/${remote_dir_rel}\"

      nix --extra-experimental-features nix-command --extra-experimental-features flakes \
        run github:nix-community/home-manager -- switch --flake .#$flake_name
    '"
  fi
}


setup_pat_macos() {
  local target="$1" user="$2"
  log "$target: storing GH_PAT in System Keychain as exo-github-pat + kick repo sync"
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail
    sudo -v
    sudo /usr/bin/security add-generic-password -U -a \"$user\" -s exo-github-pat -w \"$GH_PAT\" /Library/Keychains/System.keychain
    sudo /bin/launchctl kickstart -k system/org.nixos.exo-repo-sync 2>/dev/null || true
    sudo /bin/launchctl start system/org.nixos.exo-repo-sync 2>/dev/null || true
  '"
}

setup_pat_linux() {
  local target="$1"
  log "$target: configuring ~/.git-credentials + git credential.helper store"
  ssh_run "$target" "sh -lc '
    set -euo pipefail
    umask 077
    git config --global credential.helper store
    printf \"https://x-access-token:%s@github.com\n\" \"$GH_PAT\" > ~/.git-credentials
  '"
}

enable_linux_repo_sync_timer() {
  local target="$1" user="$2"
  log "$target: enabling linger + org.nixos.exo-repo-sync.timer"
  ssh_run_tty "$target" "sh -lc '
    set -euo pipefail
    sudo -v
    # Keep user systemd running even when not logged in
    sudo loginctl enable-linger \"$user\" || true

    # Ensure /opt/exo is user-writable for the user service
    sudo mkdir -p /opt/exo
    sudo chown \"$user\" /opt/exo || true

    # Enable timer
    systemctl --user daemon-reload || true
    systemctl --user enable --now org.nixos.exo-repo-sync.timer || true
  '"
}

main() {
  mapfile -t HOST_ENTRIES < <(read_hosts "$HOSTS")

  for entry in "${HOST_ENTRIES[@]}"; do
    read -r ssh_user ssh_target <<<"$entry"
    [[ -n "$ssh_user" && -n "$ssh_target" ]] || continue

    install_pubkey_remote "$ssh_target"
    install_nix_and_conf "$ssh_target"
    apply_flake_remote "$ssh_target" "$ssh_user"

    if remote_is_darwin "$ssh_target"; then
      setup_pat_macos "$ssh_target" "$ssh_user"
    else
      setup_pat_linux "$ssh_target"
      enable_linux_repo_sync_timer "$ssh_target" "$ssh_user"
    fi

    log "$ssh_target: bootstrap complete"
  done
}

main
