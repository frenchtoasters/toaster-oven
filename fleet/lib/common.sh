#!/usr/bin/env bash
set -euo pipefail

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { log "ERROR: $*"; exit 1; }

read_hosts() {
  local hosts_file="$1"
  [[ -f "$hosts_file" ]] || die "hosts file not found: $hosts_file"
  awk '
    /^[[:space:]]*#/ {next}
    /^[[:space:]]*$/ {next}
    NF>=2 {print $1 " " $2}
  ' "$hosts_file"
}

ssh_base_opts=(
  -o ControlMaster=auto
  -o ControlPersist=10m
  -o ControlPath="$HOME/.ssh/cm-%r@%h:%p"
  -o ServerAliveInterval=30
  -o ServerAliveCountMax=3
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

ssh_run() {
  local target="$1"; shift
  ssh "${ssh_base_opts[@]}" "$target" "$@"
}

ssh_run_tty() {
  local target="$1"; shift
  ssh -tt "${ssh_base_opts[@]}" "$target" "$@"
}

scp_to() {
  local src="$1" target="$2" dest="$3"
  scp "${ssh_base_opts[@]}" "$src" "$target:$dest"
}

rsync_to() {
  local src="$1" target="$2" dest="$3"
  rsync -az --delete -e "ssh ${ssh_base_opts[*]}" "$src" "$target:$dest"
}

remote_uname() {
  local target="$1"
  ssh_run "$target" "uname -s"
}

remote_is_darwin() { [[ "$(remote_uname "$1")" == "Darwin" ]]; }
remote_is_linux()  { [[ "$(remote_uname "$1")" == "Linux"  ]]; }

remote_nix_profile_snippet='
set -euo pipefail
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
elif [ -e /nix/var/nix/profiles/default/etc/profile.d/nix.sh ]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
fi
'
