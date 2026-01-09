#!/usr/bin/env bash
set -euo pipefail

BREW_PKGS=(uv macmon node git)

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_brew() {
  if have_cmd brew; then
    return 0
  fi

  echo "Homebrew not found. Installing..."
  # Official installer. Requires user interaction / sudo depending on system.
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Load brew into PATH for the rest of this run
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  have_cmd brew || {
    echo "ERROR: brew still not on PATH after install" >&2
    exit 1
  }
}

ensure_brew_pkgs() {
  ensure_brew
  for p in "${BREW_PKGS[@]}"; do
    if brew list --versions "$p" >/dev/null 2>&1; then
      echo "brew: $p already installed"
    else
      echo "brew: installing $p"
      brew install "$p"
    fi
  done
}

ensure_rust_nightly() {
  local rustup_bin="${HOME}/.cargo/bin/rustup"

  if [[ ! -x "${rustup_bin}" ]]; then
    echo "rustup not found. Installing..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  fi

  export PATH="${HOME}/.cargo/bin:${PATH}"

  echo "rustup: installing nightly toolchain (idempotent)"
  rustup toolchain install nightly
  rustup default nightly
}

ensure_opt_exo_dir() {
  local dest="${EXO_REPO_DEST:-/opt/exo}"

  if [[ -d "${dest}" && -w "${dest}" ]]; then
    return 0
  fi

  echo "Ensuring ${dest} exists and is owned by $(id -un)"
  sudo mkdir -p "${dest}"
  sudo chown -R "$(id -un)":staff "${dest}"
}

main() {
  ensure_brew_pkgs
  ensure_rust_nightly
  ensure_opt_exo_dir

  echo "Bootstrap complete. Next steps:"
  echo "  1) exo-repo-sync (clones/updates /opt/exo)"
  echo "  2) exo-process start (builds dashboard then runs 'uv run exo')"
}

main "$@"
