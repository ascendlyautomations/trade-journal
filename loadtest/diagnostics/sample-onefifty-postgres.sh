#!/usr/bin/env bash
# Read-only Postgres sampler for 150-VU k6 runs (every 2s → JSONL + CSV).
# Requires: psql, jq, TRADETRAXS_PROD_PERF_DATABASE_URL (or DATABASE_URL).
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SQL_FILE="$ROOT/loadtest/diagnostics/sample-onefifty-postgres.sql"
RUN_DIR="$ROOT/loadtest/diagnostics/runs"
INTERVAL_SEC="${ONEFIFTY_SAMPLE_INTERVAL_SEC:-2}"

DB_URL="${TRADETRAXS_PROD_PERF_DATABASE_URL:-${DATABASE_URL:-}}"
if [[ -z "$DB_URL" ]]; then
  echo "error: set TRADETRAXS_PROD_PERF_DATABASE_URL (or DATABASE_URL) to a read-only session connection string" >&2
  exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
  echo "error: missing $SQL_FILE" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "error: psql not found (install PostgreSQL client)" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found (required to validate samples and write CSV)" >&2
  exit 1
fi

# psql prefers these over URI components; wrong PGUSER caused silent wrong-user auth failures.
unset PGUSER PGHOST PGPORT PGDATABASE

mkdir -p "$RUN_DIR"
STAMP="$(date -u +"%Y%m%dT%H%M%SZ")-$$"
JSONL="$RUN_DIR/onefifty-pg-${STAMP}.jsonl"
CSV="$RUN_DIR/onefifty-pg-${STAMP}.csv"
ERR_LOG="$RUN_DIR/onefifty-pg-${STAMP}.errors.log"
META="$RUN_DIR/onefifty-pg-${STAMP}.meta"

is_auth_failure() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  grep -qiE 'password authentication failed|28P01|FATAL:.*authentication failed' "$f"
}

psql_sample_to_file() {
  local out_file="$1"
  local err_file="$2"
  psql "$DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -f "$SQL_FILE" -o "$out_file" 2>"$err_file"
}

compact_json_from_psql_output() {
  local raw_file="$1"
  # psql may emit pretty-printed JSON across lines; jq accepts either form.
  jq -c . "$raw_file" 2>/dev/null || jq -c . < <(tr -d '\r' <"$raw_file")
}

append_sample_artifacts() {
  local compact="$1"
  printf '%s\n' "$compact" >&3
  jq -r '[
    .sample_at,
    .connections.total,
    .connections.active,
    .connections.idle,
    .connections.waiting,
    .postgrest.total,
    .postgrest.active,
    .postgrest.idle,
    .feed_active,
    .longest_active_s,
    (.waits_by_type | tostring),
    (.feed_running | length),
    ""
  ] | @csv' <<<"$compact" >&4
}

STOP=0
AUTH_FATAL=0
trap 'STOP=1; echo "" >&2; echo "Stopping sampler (finish current sample)…" >&2' INT TERM

{
  echo "started_utc=$STAMP"
  echo "interval_sec=$INTERVAL_SEC"
  echo "jsonl=$JSONL"
  echo "csv=$CSV"
  echo "errors=$ERR_LOG"
  echo "sql=$SQL_FILE"
} >"$META"

echo "sample_at,conn_total,conn_active,conn_idle,conn_waiting,postgrest_total,postgrest_active,postgrest_idle,feed_active,longest_active_s,waits_by_type_json,feed_running_count,sample_error" >"$CSV"
: >"$JSONL"
: >"$ERR_LOG"

exec 3>>"$JSONL"
exec 4>>"$CSV"

echo "Onefifty Postgres sampler → $JSONL" >&2
echo "Interval: ${INTERVAL_SEC}s | Stop: Ctrl+C" >&2
echo "Do not redirect this script's stdout to the JSONL path (samples append via dedicated file descriptors)." >&2

# Preflight: connection + one full sample query (not counted in output files).
PREFLIGHT_ERR="$(mktemp)"
PREFLIGHT_OUT="$(mktemp)"

if ! psql "$DB_URL" -X -q -t -A -v ON_ERROR_STOP=1 -c "SELECT 1" -o "$PREFLIGHT_OUT" 2>"$PREFLIGHT_ERR"; then
  if is_auth_failure "$PREFLIGHT_ERR"; then
    echo "error: database authentication failed (check URL password or PGPASSWORD; unset PGUSER if set)" >&2
    cat "$PREFLIGHT_ERR" >&2
    rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"
    exit 2
  fi
  echo "error: preflight connection check failed" >&2
  cat "$PREFLIGHT_ERR" >&2
  rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"
  exit 1
fi

if ! psql_sample_to_file "$PREFLIGHT_OUT" "$PREFLIGHT_ERR"; then
  if is_auth_failure "$PREFLIGHT_ERR"; then
    echo "error: database authentication failed during sample query preflight" >&2
    cat "$PREFLIGHT_ERR" >&2
    rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"
    exit 2
  fi
  echo "error: preflight sample query failed" >&2
  cat "$PREFLIGHT_ERR" >&2
  rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"
  exit 1
fi

if ! compact_json_from_psql_output "$PREFLIGHT_OUT" >/dev/null; then
  echo "error: preflight sample query did not return valid JSON (see $SQL_FILE)" >&2
  cat "$PREFLIGHT_OUT" >&2
  rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"
  exit 1
fi

rm -f "$PREFLIGHT_ERR" "$PREFLIGHT_OUT"

ERR=0
while [[ "$STOP" -eq 0 ]]; do
  SAMPLE_ERR="$(mktemp)"
  SAMPLE_OUT="$(mktemp)"
  if psql_sample_to_file "$SAMPLE_OUT" "$SAMPLE_ERR"; then
    if [[ -s "$SAMPLE_ERR" ]]; then
      cat "$SAMPLE_ERR" >>"$ERR_LOG"
    fi
    if COMPACT="$(compact_json_from_psql_output "$SAMPLE_OUT" 2>>"$ERR_LOG")"; then
      LINES_BEFORE="$(wc -l <"$JSONL" | tr -d ' ')"
      if append_sample_artifacts "$COMPACT" 2>>"$ERR_LOG"; then
        LINES_AFTER="$(wc -l <"$JSONL" | tr -d ' ')"
        if [[ "$LINES_AFTER" -ne $((LINES_BEFORE + 1)) ]]; then
          ERR=$((ERR + 1))
          TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
          printf '%s\n' "${TS},,,,,,,,,,,,jsonl_append_failed" >&4
          echo "$TS jsonl append failed (lines before=$LINES_BEFORE after=$LINES_AFTER)" >>"$ERR_LOG"
        fi
      else
        ERR=$((ERR + 1))
        TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf '%s\n' "${TS},,,,,,,,,,,,artifact_write_failed" >&4
        echo "$TS failed to write JSONL/CSV row" >>"$ERR_LOG"
      fi
    else
      ERR=$((ERR + 1))
      TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf '%s\n' "${TS},,,,,,,,,,,,invalid_json" >&4
      echo "$TS invalid JSON from psql:" >>"$ERR_LOG"
      cat "$SAMPLE_OUT" >>"$ERR_LOG"
    fi
  else
    if is_auth_failure "$SAMPLE_ERR"; then
      cat "$SAMPLE_ERR" >>"$ERR_LOG"
      echo "fatal: database authentication failed; stopping sampler" >&2
      AUTH_FATAL=1
      rm -f "$SAMPLE_ERR" "$SAMPLE_OUT"
      break
    fi
    ERR=$((ERR + 1))
    TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '%s\n' "${TS},,,,,,,,,,,,psql_failed" >&4
    if [[ -s "$SAMPLE_ERR" ]]; then
      echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") psql failed:" >>"$ERR_LOG"
      cat "$SAMPLE_ERR" >>"$ERR_LOG"
    else
      echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") psql failed (no stderr)" >>"$ERR_LOG"
    fi
  fi
  rm -f "$SAMPLE_ERR" "$SAMPLE_OUT"

  if [[ "$STOP" -eq 1 ]]; then
    break
  fi
  sleep "$INTERVAL_SEC"
done

exec 3>&-
exec 4>&-

SAMPLES_OK="$(wc -l <"$JSONL" | tr -d ' ')"
CSV_ROWS=$(( $(wc -l <"$CSV") - 1 ))

{
  echo "stopped_utc=$(date -u +"%Y%m%dT%H%M%SZ")"
  echo "samples_ok=$SAMPLES_OK"
  echo "jsonl_lines=$SAMPLES_OK"
  echo "csv_data_rows=$CSV_ROWS"
  echo "sample_errors=$ERR"
} >>"$META"

echo "Done: $SAMPLES_OK samples → $JSONL" >&2
[[ "$ERR" -gt 0 ]] && echo "Warnings: $ERR sample errors (see $ERR_LOG)" >&2
if [[ "$SAMPLES_OK" -ne "$CSV_ROWS" ]]; then
  echo "Warning: JSONL lines ($SAMPLES_OK) != CSV data rows ($CSV_ROWS)" >&2
fi

if [[ "$AUTH_FATAL" -eq 1 ]]; then
  exit 2
fi
exit 0
