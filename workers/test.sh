#!/usr/bin/env bash
# Compost worker demo smoke checks.
#
# Default mode is safe: TypeScript check, ping, sync status, and sync previews.
# Use --write to trigger live sync writes. Use --apply-tools to run tidyNow.

set -euo pipefail

cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: bash ./test.sh [--write] [--apply-tools] [--skip-previews] [--skip-logs]

Safe default:
  - npm run check
  - remote ping
  - sync status health check
  - preview cue, sleepOnItReviewer, gardener, sleepOnItCleanup

Options:
  --write          Trigger cue, sleepOnItReviewer, and gardener for real writes.
  --apply-tools    Run tidyNow/applyApproved. This can change approved Notion pages.
  --skip-previews  Skip sync previews.
  --skip-logs      Skip latest run logs.

Set COMPOST_WORKER_ID when workers.json is absent:
  COMPOST_WORKER_ID=019e31dc-050f-7a85-974a-21954fd261f5 bash ./test.sh
EOF
}

WRITE=0
APPLY_TOOLS=0
SKIP_PREVIEWS=0
SKIP_LOGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) WRITE=1 ;;
    --apply-tools) APPLY_TOOLS=1 ;;
    --skip-previews) SKIP_PREVIEWS=1 ;;
    --skip-logs) SKIP_LOGS=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

find_ntn() {
  if [[ -n "${NTN_BIN:-}" ]]; then
    printf '%s\n' "$NTN_BIN"
    return
  fi
  if command -v ntn >/dev/null 2>&1; then
    command -v ntn
    return
  fi
  if [[ -x "$HOME/.local/bin/ntn" ]]; then
    printf '%s\n' "$HOME/.local/bin/ntn"
    return
  fi
  echo "ntn CLI not found. Install it or set NTN_BIN=/path/to/ntn." >&2
  exit 127
}

env_value() {
  local key="$1"
  local file
  local value
  for file in .env .env.example; do
    [[ -f "$file" ]] || continue
    value="$(awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file")"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return
    fi
  done
}

NTN="$(find_ntn)"
WORKER_ID="${COMPOST_WORKER_ID:-$(env_value COMPOST_WORKER_ID)}"
WORKER_ARGS=()

if [[ -n "$WORKER_ID" ]]; then
  WORKER_ARGS=(--worker-id "$WORKER_ID")
elif [[ ! -f workers.json ]]; then
  echo "No workers.json and no COMPOST_WORKER_ID. Set COMPOST_WORKER_ID or run from deployed workers directory." >&2
  exit 2
fi

section() {
  printf '\n==> %s\n' "$1"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

section "TypeScript check"
run npm run check

section "Remote ping"
run "$NTN" workers exec "${WORKER_ARGS[@]}" ping -d '{}'

section "Sync status"
STATUS_OUTPUT="$("$NTN" workers sync status "${WORKER_ARGS[@]}" --plain --no-watch)"
printf '%s\n' "$STATUS_OUTPUT"

for key in cue sleepOnItReviewer gardener sleepOnItCleanup; do
  if ! printf '%s\n' "$STATUS_OUTPUT" | awk -F '\t' -v key="$key" '$1 == key && $0 ~ /healthy/ { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "Sync $key is missing or not healthy." >&2
    exit 1
  fi
done

if [[ "$SKIP_PREVIEWS" -eq 0 ]]; then
  section "Sync previews"
  for key in cue sleepOnItReviewer gardener sleepOnItCleanup; do
    run "$NTN" workers sync trigger "${WORKER_ARGS[@]}" "$key" --preview
  done
fi

if [[ "$WRITE" -eq 1 ]]; then
  section "Live demo sync triggers"
  for key in cue sleepOnItReviewer gardener; do
    run "$NTN" workers sync trigger "${WORKER_ARGS[@]}" "$key"
  done
else
  section "Live writes skipped"
  echo "Use --write only when you want to mutate managed DB rows for the live demo."
fi

if [[ "$APPLY_TOOLS" -eq 1 ]]; then
  section "Apply approved tools"
  run "$NTN" workers exec "${WORKER_ARGS[@]}" tidyNow -d '{}'
  run "$NTN" workers exec "${WORKER_ARGS[@]}" applyApproved -d '{}'
else
  section "Apply tools skipped"
  echo "Use --apply-tools only after approving rows in Compost Pile."
fi

if [[ "$SKIP_LOGS" -eq 0 ]]; then
  section "Latest run logs"
  latest_run="$("$NTN" workers runs list --plain 2>/dev/null | head -n 1 | awk '{ print $1 }' || true)"
  if [[ -n "$latest_run" ]]; then
    "$NTN" workers runs logs "$latest_run" 2>/dev/null | tail -20 || true
  else
    echo "No recent run ID found."
  fi
fi

section "Result"
echo "Smoke check complete. Use workers/docs/DEMO-RUNBOOK.md for the reset and rehearsal flow."
