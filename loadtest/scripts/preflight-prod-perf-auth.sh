#!/usr/bin/env bash
# Verify each LOADTEST_USERS_JSON account can obtain a JWT (no tokens printed).
# Run separately from k6 — do not chain immediately before `k6 run` (duplicate grants → Auth 429).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/loadtest/.env.production-perf"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "error: missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

[[ "${LOADTEST_ENV:-}" == "production" ]] || { echo "error: LOADTEST_ENV must be production" >&2; exit 1; }
[[ -n "${LOADTEST_SUPABASE_URL:-}" ]] || { echo "error: LOADTEST_SUPABASE_URL unset" >&2; exit 1; }
[[ -n "${LOADTEST_SUPABASE_ANON_KEY:-}" ]] || { echo "error: LOADTEST_SUPABASE_ANON_KEY unset" >&2; exit 1; }

python3 - <<'PY' "$LOADTEST_USERS_JSON" "$LOADTEST_SUPABASE_URL" "$LOADTEST_SUPABASE_ANON_KEY"
import json, sys, time, urllib.request, urllib.error

users = json.loads(sys.argv[1])
GRANT_SPACING_SEC = 0.85
MAX_429_RETRIES = 6
base = sys.argv[2].rstrip("/")
anon = sys.argv[3]
url = f"{base}/auth/v1/token?grant_type=password"

def mask_email(email: str) -> str:
    email = (email or "").strip()
    if "@" not in email:
        return "(invalid)"
    local, dom = email.split("@", 1)
    if len(local) <= 2:
        return f"**@{dom}"
    return f"{local[:2]}***@{dom}"


def redact_sensitive(text: str) -> str:
    import re

    out = text or ""
    for pat in (
        r'access_token["\']?\s*[:=]\s*["\']?[^"\'\s,}]+',
        r'refresh_token["\']?\s*[:=]\s*["\']?[^"\'\s,}]+',
        r'password["\']?\s*[:=]\s*["\']?[^"\'\s,}]+',
        r"Bearer\s+[A-Za-z0-9._-]+",
    ):
        out = re.sub(pat, "[redacted]", out, flags=re.I)
    return out


def describe_auth_failure(http_status: int, body: str) -> str:
    if http_status == 0:
        return "HTTP 0 client_timeout_or_network (timeout or connection error)"
    try:
        payload = json.loads(body)
        if isinstance(payload, dict):
            code = (
                payload.get("error_code")
                or payload.get("code")
                or payload.get("error")
                or "auth_error"
            )
            msg = (
                payload.get("msg")
                or payload.get("error_description")
                or payload.get("message")
                or payload.get("error")
                or ""
            )
            detail = redact_sensitive(str(msg))[:240]
            return f"HTTP {http_status} {code}" + (f" — {detail}" if detail else "")
    except json.JSONDecodeError:
        pass
    snippet = redact_sensitive((body or "")[:240])
    return f"HTTP {http_status} auth_http_{http_status}" + (f" — {snippet}" if snippet else "")

ok = 0
fail = 0
skip = 0

for i, u in enumerate(users):
    email = (u.get("email") or "").strip()
    password = u.get("password") or ""
    label = mask_email(email)
    if not email or not password:
        print(f"user[{i}] {label}: error missing email or password")
        fail += 1
        continue
    if email.startswith("REPLACE_WITH_") or password.startswith("REPLACE_WITH_"):
        print(f"user[{i}] {label}: skip placeholder")
        skip += 1
        continue
    body = json.dumps({"email": email, "password": password}).encode()
    last_err = None
    for attempt in range(MAX_429_RETRIES):
        if attempt > 0:
            time.sleep(min(2 ** attempt, 12))
        elif i > 0:
            time.sleep(GRANT_SPACING_SEC)
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "apikey": anon,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status != 200:
                    last_err = f"HTTP {resp.status}"
                    continue
                payload = json.loads(resp.read().decode())
                if not payload.get("access_token"):
                    last_err = "no access_token in response"
                    continue
                print(f"user[{i}] {label}: ok (expires_in={payload.get('expires_in', '?')}s)")
                ok += 1
                last_err = None
                break
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            last_err = describe_auth_failure(e.code, body)
            if e.code != 429:
                break
        except Exception as e:
            last_err = describe_auth_failure(0, str(e))
            break
    if last_err is not None:
        print(f"user[{i}] {label}: error {last_err}")
        fail += 1

print(f"summary: ok={ok} fail={fail} skip={skip} total={len(users)}")
if fail > 0:
    raise SystemExit(1)
if ok == 0:
    raise SystemExit("no accounts authenticated")
PY
