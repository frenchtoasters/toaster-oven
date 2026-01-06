#!/usr/bin/env bash
set -euo pipefail

DEFAULT_WIRED_LIMIT_PERCENT=85
DEFAULT_WIRED_LWM_PERCENT=75

# Prefer env vars if present (for launchd), otherwise use args, otherwise defaults.
WIRED_LIMIT_PERCENT="${WIRED_LIMIT_PERCENT:-${1:-$DEFAULT_WIRED_LIMIT_PERCENT}}"
WIRED_LWM_PERCENT="${WIRED_LWM_PERCENT:-${2:-$DEFAULT_WIRED_LWM_PERCENT}}"

# Validate 0-100
if [[ "$WIRED_LIMIT_PERCENT" -lt 0 || "$WIRED_LIMIT_PERCENT" -gt 100 || \
      "$WIRED_LWM_PERCENT"   -lt 0 || "$WIRED_LWM_PERCENT"   -gt 100 ]]; then
  echo "Error: Percentages must be between 0 and 100." >&2
  exit 1
fi

TOTAL_MEM_MB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
WIRED_LIMIT_MB=$(( TOTAL_MEM_MB * WIRED_LIMIT_PERCENT / 100 ))
WIRED_LWM_MB=$(( TOTAL_MEM_MB * WIRED_LWM_PERCENT / 100 ))

echo "Total memory: $TOTAL_MEM_MB MB"
echo "Maximum limit (iogpu.wired_limit_mb): $WIRED_LIMIT_MB MB ($WIRED_LIMIT_PERCENT%)"
echo "Lower bound (iogpu.wired_lwm_mb): $WIRED_LWM_MB MB ($WIRED_LWM_PERCENT%)"

sudo sysctl -w iogpu.wired_limit_mb="$WIRED_LIMIT_MB"
sudo sysctl -w iogpu.wired_lwm_mb="$WIRED_LWM_MB"

ACT_LIMIT="$(sysctl -n iogpu.wired_limit_mb || true)"
ACT_LWM="$(sysctl -n iogpu.wired_lwm_mb || true)"

echo "Readback: iogpu.wired_limit_mb=$ACT_LIMIT"
echo "Readback: iogpu.wired_lwm_mb=$ACT_LWM"

if [[ "$ACT_LIMIT" -ne "$WIRED_LIMIT_MB" || "$ACT_LWM" -ne "$WIRED_LWM_MB" ]]; then
  echo "ERROR: sysctl values did not stick (expected $WIRED_LIMIT_MB/$WIRED_LWM_MB, got $ACT_LIMIT/$ACT_LWM)" >&2
  exit 2
fi
