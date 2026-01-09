#!/usr/bin/env bash
set -euo pipefail

REPO_HTTPS_URL="${EXO_REPO_URL_HTTPS:-https://github.com/exo-explore/exo.git}"
DEST="${EXO_REPO_DEST:-/opt/exo}"
OWNER="${EXO_REPO_OWNER:-$(id -un)}"

# Target selection (in order of priority):
# - EXO_REPO_REF: any git ref-ish thing (main, feature/..., tag, SHA, refs/..., pull/123/head)
# - EXO_REPO_PR: PR number (fetches pull/<n>/head)
# - EXO_REPO_BRANCH: branch name (default main)
REF="${EXO_REPO_REF:-}"
PR="${EXO_REPO_PR:-}"
BRANCH="${EXO_REPO_BRANCH:-main}"

GIT_BIN="${GIT:-git}"

# Optional token support (useful if you ever point at private forks)
TOKEN="$(/usr/bin/security find-generic-password -s exo-github-pat -w 2>/dev/null || \
         /usr/bin/security find-generic-password -s exo-github-pat -w /Library/Keychains/System.keychain 2>/dev/null || true)"
AUTH_EXTRA=()
if [[ -n "${TOKEN}" ]]; then
  AUTH="Authorization: Basic $(printf 'x-access-token:%s' "$TOKEN" | /usr/bin/base64)"
  AUTH_EXTRA=( -c "http.extraHeader=${AUTH}" )
fi

# Resolve target ref
if [[ -n "${PR}" ]]; then
  REF="pull/${PR}/head"
elif [[ -z "${REF}" ]]; then
  REF="${BRANCH}"
fi

mkdir -p "${DEST}"
/usr/sbin/chown -R "${OWNER}":staff "${DEST}" || true

clone_if_needed() {
  if [[ ! -d "${DEST}/.git" ]]; then
    echo "exo-repo-sync: cloning ${REPO_HTTPS_URL} -> ${DEST}"
    "${GIT_BIN}" "${AUTH_EXTRA[@]}" clone "${REPO_HTTPS_URL}" "${DEST}"
  fi
}

# Checkout helpers
checkout_branch() {
  local b="$1"
  echo "exo-repo-sync: checkout branch ${b}"
  "${GIT_BIN}" "${AUTH_EXTRA[@]}" fetch origin "${b}" --prune
  "${GIT_BIN}" switch -C "${b}" --track "origin/${b}" 2>/dev/null || "${GIT_BIN}" switch "${b}" || true
  "${GIT_BIN}" reset --hard "origin/${b}"
}

checkout_pr() {
  local pr="$1"
  local name="pr-${pr}"
  echo "exo-repo-sync: checkout PR #${pr} (${name})"
  "${GIT_BIN}" "${AUTH_EXTRA[@]}" fetch origin "pull/${pr}/head:${name}" --force
  "${GIT_BIN}" switch "${name}" || "${GIT_BIN}" switch -c "${name}"
  "${GIT_BIN}" reset --hard "${name}"
}

checkout_ref_generic() {
  local r="$1"

  # PR ref patterns
  if [[ "${r}" =~ ^pull/([0-9]+)/head$ ]]; then
    checkout_pr "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "${r}" =~ ^refs/pull/([0-9]+)/head$ ]]; then
    checkout_pr "${BASH_REMATCH[1]}"
    return 0
  fi

  # If it looks like a full ref (refs/...), fetch it directly and detach
  if [[ "${r}" == refs/* ]]; then
    echo "exo-repo-sync: checkout ref ${r} (detached)"
    "${GIT_BIN}" "${AUTH_EXTRA[@]}" fetch origin "${r}" --prune
    "${GIT_BIN}" checkout --detach FETCH_HEAD
    return 0
  fi

  # If it's a SHA, detach to it (fetch all first so it exists)
  if [[ "${r}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    echo "exo-repo-sync: checkout commit ${r} (detached)"
    "${GIT_BIN}" "${AUTH_EXTRA[@]}" fetch origin --tags --prune
    "${GIT_BIN}" checkout --detach "${r}"
    return 0
  fi

  # Try as branch first; if that fails, try as tag
  if "${GIT_BIN}" show-ref --verify --quiet "refs/remotes/origin/${r}" 2>/dev/null; then
    checkout_branch "${r}"
    return 0
  fi

  echo "exo-repo-sync: treating '${r}' as branch/tag"
  "${GIT_BIN}" "${AUTH_EXTRA[@]}" fetch origin --tags --prune
  if "${GIT_BIN}" ls-remote --exit-code --heads origin "${r}" >/dev/null 2>&1; then
    checkout_branch "${r}"
    return 0
  fi

  # tags or other refs
  if "${GIT_BIN}" rev-parse -q --verify "refs/tags/${r}" >/dev/null 2>&1; then
    echo "exo-repo-sync: checkout tag ${r} (detached)"
    "${GIT_BIN}" checkout --detach "${r}"
    return 0
  fi

  echo "exo-repo-sync: ERROR: could not resolve ref '${r}'" >&2
  echo "Try EXO_REPO_BRANCH=<branch>, EXO_REPO_PR=<number>, or EXO_REPO_REF=<git-ref>" >&2
  exit 2
}

clone_if_needed
cd "${DEST}"

# Ensure origin URL
"${GIT_BIN}" remote set-url origin "${REPO_HTTPS_URL}" || true

checkout_ref_generic "${REF}"

/usr/sbin/chown -R "${OWNER}":staff "${DEST}" || true

echo "exo-repo-sync: ok (ref=${REF}, dest=${DEST})"
