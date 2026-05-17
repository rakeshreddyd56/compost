#!/usr/bin/env bash
# Compost worker demo smoke checks.
#
# Default mode is safe: TypeScript check, ping, sync status, and sync previews.
# Use --write to trigger live sync writes. Use --apply-tools to run tidyNow
# and the applyProposal contract check. Use --reset-demo to restore safe demo rows.

set -euo pipefail

cd "$(dirname "$0")"

usage() {
  cat <<'EOF'
Usage: bash ./test.sh [--write] [--apply-tools] [--apply-proposal ID] [--review-draft ID DECISION] [--reset-demo] [--legacy-apply-approved] [--skip-previews] [--skip-logs]

Safe default:
  - npm run check
  - remote ping
  - sync status health check
  - preview cue, sleepOnItReviewer, gardener, sleepOnItCleanup

Options:
  --write                  Trigger cue, sleepOnItReviewer, and gardener for real writes.
  --apply-tools            Run tidyNow and verify applyProposal's ok=false contract.
  --apply-proposal ID      Apply one explicit safe demo proposal through applyProposal.
  --review-draft ID DECISION
                           Review one explicit safe demo draft. DECISION is approve or reject.
  --reset-demo             Restore/expire only safe demo rows, reset sync state, and retrigger demo syncs.
  --legacy-apply-approved  Also run the legacy batch applyApproved tool.
  --skip-previews          Skip sync previews.
  --skip-logs              Skip latest run logs.

Set COMPOST_WORKER_ID when workers.json is absent:
  COMPOST_WORKER_ID=019e31dc-050f-7a85-974a-21954fd261f5 bash ./test.sh
EOF
}

WRITE=0
APPLY_TOOLS=0
APPLY_PROPOSAL_ID="${COMPOST_DEMO_PROPOSAL_ID:-}"
REVIEW_DRAFT_ID="${COMPOST_DEMO_DRAFT_ID:-}"
REVIEW_DRAFT_DECISION="${COMPOST_DEMO_DRAFT_DECISION:-}"
RESET_DEMO=0
LEGACY_APPLY_APPROVED=0
SKIP_PREVIEWS=0
SKIP_LOGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --write) WRITE=1 ;;
    --apply-tools) APPLY_TOOLS=1 ;;
    --apply-proposal)
      shift
      if [[ $# -eq 0 || -z "${1:-}" ]]; then
        echo "--apply-proposal requires a Proposal ID" >&2
        exit 2
      fi
      APPLY_PROPOSAL_ID="$1"
      APPLY_TOOLS=1
      ;;
    --review-draft)
      shift
      if [[ $# -lt 2 || -z "${1:-}" || -z "${2:-}" ]]; then
        echo "--review-draft requires a Draft ID and decision (approve|reject)" >&2
        exit 2
      fi
      REVIEW_DRAFT_ID="$1"
      REVIEW_DRAFT_DECISION="$2"
      shift
      ;;
    --reset-demo) RESET_DEMO=1 ;;
    --legacy-apply-approved) LEGACY_APPLY_APPROVED=1 ;;
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

if [[ "$RESET_DEMO" -eq 1 ]]; then
  section "Safe demo reset"
  run node ./scripts/reset-demo-state.mjs
  for key in cue sleepOnItReviewer gardener; do
    run "$NTN" workers sync state reset "${WORKER_ARGS[@]}" "$key"
    run "$NTN" workers sync trigger "${WORKER_ARGS[@]}" "$key"
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
  section "Tidy proposal refresh"
  run "$NTN" workers exec "${WORKER_ARGS[@]}" tidyNow -d '{}'

  section "applyProposal missing-row contract"
  set +e
  missing_output="$("$NTN" workers exec "${WORKER_ARGS[@]}" applyProposal -d '{"proposalId":"__missing_smoke__"}' 2>&1)"
  missing_status=$?
  set -e
  printf '%s\n' "$missing_output"
  if [[ "$missing_status" -ne 0 ]]; then
    echo "applyProposal missing-row check failed at CLI level." >&2
    exit "$missing_status"
  fi
  if ! printf '%s\n' "$missing_output" | grep -Eq '"ok"[[:space:]]*:[[:space:]]*false|proposal not found'; then
    echo "applyProposal should return ok=false for a missing proposal." >&2
    exit 1
  fi

  if [[ -n "$APPLY_PROPOSAL_ID" ]]; then
    section "Apply explicit safe demo proposal"
    run "$NTN" workers exec "${WORKER_ARGS[@]}" applyProposal -d "{\"proposalId\":\"$APPLY_PROPOSAL_ID\"}"
  else
    section "Explicit proposal apply skipped"
    echo "Set COMPOST_DEMO_PROPOSAL_ID or pass --apply-proposal ID to mutate one safe demo target."
  fi

  if [[ "$LEGACY_APPLY_APPROVED" -eq 1 ]]; then
    section "Legacy batch applyApproved"
    run "$NTN" workers exec "${WORKER_ARGS[@]}" applyApproved -d '{}'
  fi
else
  section "Apply tools skipped"
  echo "Use --apply-tools to refresh proposals and verify applyProposal; pass --apply-proposal ID to mutate one safe demo target."
fi

if [[ -n "$REVIEW_DRAFT_ID" || -n "$REVIEW_DRAFT_DECISION" ]]; then
  if [[ -z "$REVIEW_DRAFT_ID" || -z "$REVIEW_DRAFT_DECISION" ]]; then
    echo "Set both COMPOST_DEMO_DRAFT_ID and COMPOST_DEMO_DRAFT_DECISION, or pass --review-draft ID DECISION." >&2
    exit 2
  fi
  if [[ "$REVIEW_DRAFT_DECISION" != "approve" && "$REVIEW_DRAFT_DECISION" != "reject" ]]; then
    echo "reviewDraft decision must be approve or reject." >&2
    exit 2
  fi
  section "Review explicit safe demo draft"
  run "$NTN" workers exec "${WORKER_ARGS[@]}" reviewDraft -d "{\"draftId\":\"$REVIEW_DRAFT_ID\",\"decision\":\"$REVIEW_DRAFT_DECISION\"}"
else
  section "Draft review skipped"
  echo "Pass --review-draft ID approve|reject to certify one safe demo draft."
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
