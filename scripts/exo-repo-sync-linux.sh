#!/usr/bin/env bash
set -euo pipefail

REPO_HTTPS_URL="${EXO_REPO_URL_HTTPS:-https://github.com/exo-explore/exo-v2.git}"
BRANCH="${EXO_REPO_BRANCH:-big-refactor}"
DEST="${EXO_REPO_DEST:-/opt/exo}"

log() { echo "[exo-repo-sync-linux] $*" >&2; }

mkdir -p "$DEST"

if [[ ! -w "$DEST" ]]; then
  log "ERROR: DEST '$DEST' is not writable by $(id -un)."
  log "Fix: sudo chown -R $(id -un):$(id -gn) '$DEST'"
  exit 1
fi

if [[ ! -d "$DEST/.git" ]]; then
  log "Cloning $REPO_HTTPS_URL (branch=$BRANCH) -> $DEST"
  rm -rf "$DEST"/*
  git clone --single-branch --branch "$BRANCH" "$REPO_HTTPS_URL" "$DEST"
  exit 0
fi

cd "$DEST"
log "Syncing $DEST to origin/$BRANCH"

git remote set-url origin "$REPO_HTTPS_URL" || true
git fetch origin

git switch -C "$BRANCH" --track "origin/$BRANCH" 2>/dev/null || git switch "$BRANCH" || true
git reset --hard "origin/$BRANCH"
git clean -fd

log "Done."
