#!/usr/bin/env bash
# Standalone Rithmic Test Phase 1 auth diagnostic (live gateway).
# Uses developer test credentials from the environment only — never prints secrets.
#
# Compares npm run rithmic:phase1-discovery at HEAD vs commit 8ddf3771 (same credentials).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASELINE_REF="${RITHMIC_DIAG_BASELINE_REF:-8ddf3771}"
WORKTREE_DIR="${RITHMIC_DIAG_WORKTREE_DIR:-$ROOT/.cache/rithmic-diag-worktree-baseline}"
OUT_DIR="${RITHMIC_DIAG_OUT_DIR:-$ROOT/.cache/rithmic-diag-results}"
mkdir -p "$OUT_DIR"

load_rithmic_env() {
  if [[ -f "$ROOT/.env.local" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z "$line" ]] && continue
      case "$line" in
        RITHMIC_*=*)
          export "$line"
          ;;
      esac
    done <"$ROOT/.env.local"
  fi
}

load_rithmic_env

if [[ -z "${RITHMIC_API_USER:-}" || -z "${RITHMIC_API_PASSWORD:-}" ]]; then
  echo "Missing credentials. Set RITHMIC_API_USER and RITHMIC_API_PASSWORD in the environment or .env.local." >&2
  exit 1
fi

export RITHMIC_API_ENV="${RITHMIC_API_ENV:-test}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for the comparison summary (brew install jq)." >&2
  exit 1
fi

ensure_worktree() {
  if [[ ! -d "$WORKTREE_DIR/.git" ]]; then
    mkdir -p "$(dirname "$WORKTREE_DIR")"
    git worktree add --detach "$WORKTREE_DIR" "$BASELINE_REF"
  fi
  if [[ ! -e "$WORKTREE_DIR/node_modules" ]]; then
    ln -sf "$ROOT/node_modules" "$WORKTREE_DIR/node_modules"
  fi
}

run_discovery() {
  local label="$1"
  local dir="$2"
  local out_file="$3"
  (
    cd "$dir"
    npm run rithmic:phase1-discovery >"$out_file" 2>"$OUT_DIR/${label}.stderr.log"
  )
  local exit_code=$?
  if [[ $exit_code -ne 0 && ! -s "$out_file" ]]; then
    echo "[$label] discovery failed (exit $exit_code). See $OUT_DIR/${label}.stderr.log" >&2
    return "$exit_code"
  fi
  return 0
}

summarize() {
  local label="$1"
  local ref="$2"
  local json_file="$3"
  if [[ ! -s "$json_file" ]]; then
    echo "{\"label\":\"$label\",\"gitRef\":\"$ref\",\"error\":\"empty_or_missing_json\"}"
    return
  fi
  jq -c \
    --arg label "$label" \
    --arg ref "$ref" \
    '{
      label: $label,
      gitRef: $ref,
      ok,
      apiEnvironment,
      wssUrl,
      systemNames,
      selectedSystemName,
      infraTypeLabel,
      loginAttempted,
      loginSuccess,
      loginRpCode,
      agreementRequired,
      accountListRpCode,
      accountCount,
      failureStage,
      lastSuccessfulStage,
      diagnostics
    }' "$json_file"
}

cleanup_worktree() {
  if [[ "${RITHMIC_DIAG_KEEP_WORKTREE:-0}" != "1" ]]; then
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
  fi
}
trap cleanup_worktree EXIT

CURRENT_JSON="$OUT_DIR/head.json"
BASELINE_JSON="$OUT_DIR/baseline.json"

echo "Running Phase 1 discovery at HEAD (current tree)…"
run_discovery "head" "$ROOT" "$CURRENT_JSON" || true

ensure_worktree
echo "Running Phase 1 discovery at $BASELINE_REF (detached worktree)…"
run_discovery "baseline" "$WORKTREE_DIR" "$BASELINE_JSON" || true

echo ""
echo "=== Rithmic Phase 1 auth diagnostic (no credentials in output) ==="
echo ""
summarize "current" "HEAD" "$CURRENT_JSON" | jq .
echo ""
summarize "baseline" "$BASELINE_REF" "$BASELINE_JSON" | jq .
echo ""
echo "Full JSON (redacted): $CURRENT_JSON , $BASELINE_JSON"
echo "Stderr logs: $OUT_DIR/head.stderr.log , $OUT_DIR/baseline.stderr.log"