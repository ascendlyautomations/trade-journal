#!/usr/bin/env python3
"""
Recover lost passwords for prod perf accounts perfload51–83 (realistic600_full).

Uses Supabase Admin Auth (service_role) to set new passwords on existing Auth users
(UUID unchanged — profiles, follows, and fixture rows stay linked).

Default: --dry-run (list allowlisted users + recovery file state only).
Live: --execute plus TRADETRAXS_RECOVER_REALISTIC600_PERF=yes.

Never logs passwords, service_role keys, or full credential JSON.

Usage:
  export SUPABASE_SERVICE_ROLE_KEY='…'   # from secure store (e.g. .env.local), not loadtest anon env
  set -a && source loadtest/.env.production-perf && set +a

  python3 loadtest/scripts/recover-realistic600-perf-passwords.py
  TRADETRAXS_RECOVER_REALISTIC600_PERF=yes python3 loadtest/scripts/recover-realistic600-perf-passwords.py --execute
"""
from __future__ import annotations

import argparse
import base64
import importlib.util
import json
import os
import random
import secrets
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / "loadtest" / ".env.production-perf"
RECOVERY_DIR = ROOT / "loadtest" / ".recovery"
RECOVERY_FILE = RECOVERY_DIR / "realistic600-perf-passwords.json"
RECOVERY_SCHEMA_VERSION = 1
PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"
REALISTIC600_USER_COUNT = 100
ONEFIFTY_USER_COUNT = 50
DEFAULT_PACE_SEC = 3.0
AUTH_MAX_RETRIES = 12
EXECUTE_CONFIRM_ENV = "TRADETRAXS_RECOVER_REALISTIC600_PERF"


def load_provision_module():
    path = Path(__file__).resolve().parent / "provision-prod-perf-accounts.py"
    spec = importlib.util.spec_from_file_location("provision_prod_perf_accounts", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("failed to load provision-prod-perf-accounts.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def allowlisted_emails() -> list[str]:
    return [f"tradetraxsdemo+perfload{n}@gmail.com" for n in range(51, 84)]


def normalize_env_secret(raw: str) -> str:
    s = raw.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ("'", '"'):
        s = s[1:-1].strip()
    return s


def jwt_payload_unverified(token: str) -> dict:
    """Decode JWT payload (signature not verified — shape/role gate only)."""
    token = normalize_env_secret(token)
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("invalid JWT shape")
    part = parts[1]
    part += "=" * (-len(part) % 4)
    try:
        data = json.loads(base64.urlsafe_b64decode(part.encode()))
    except (json.JSONDecodeError, ValueError) as e:
        raise ValueError("invalid JWT payload") from e
    if not isinstance(data, dict):
        raise ValueError("invalid JWT payload")
    return data


def assert_service_role_key(service_role: str, anon: str, base: str) -> str:
    """Return normalized key; refuse anon keys and non–service_role JWTs."""
    key = normalize_env_secret(service_role)
    if not key:
        raise SystemExit("error: set SUPABASE_SERVICE_ROLE_KEY (service_role, not anon)")
    anon_norm = normalize_env_secret(anon)
    if key == anon_norm:
        raise SystemExit("error: SUPABASE_SERVICE_ROLE_KEY must not be the loadtest anon key")

    try:
        payload = jwt_payload_unverified(key)
    except ValueError:
        raise SystemExit("error: SUPABASE_SERVICE_ROLE_KEY is not a valid JWT") from None

    role = payload.get("role")
    if role != "service_role":
        raise SystemExit(
            f"error: SUPABASE_SERVICE_ROLE_KEY JWT role must be service_role (got {role!r})"
        )

    ref = payload.get("ref")
    if ref and str(ref) != PRODUCTION_PROJECT_REF:
        raise SystemExit(
            f"error: SUPABASE_SERVICE_ROLE_KEY project ref {ref!r} != production {PRODUCTION_PROJECT_REF}"
        )
    if PRODUCTION_PROJECT_REF not in base:
        raise SystemExit(f"error: LOADTEST_SUPABASE_URL must include production ref {PRODUCTION_PROJECT_REF}")

    return key


def verify_admin_auth_read_access(base: str, service_role: str) -> None:
    """Read-only Admin Auth probe (list 1 user); confirms key can call admin routes."""
    headers = {
        "apikey": service_role,
        "Authorization": f"Bearer {service_role}",
    }
    q = urllib.parse.urlencode({"page": 1, "per_page": 1})
    status, payload, _ = http_json("GET", f"{base}/auth/v1/admin/users?{q}", headers=headers)
    if status == 200 and isinstance(payload, dict) and isinstance(payload.get("users"), list):
        return
    if status in (401, 403):
        raise SystemExit(
            f"error: Admin Auth read check denied (HTTP {status}); key is not authorized for admin users"
        )
    raise SystemExit(f"error: Admin Auth read check failed (HTTP {status})")


def slot_for_email(email: str) -> int:
    """LOADTEST_REALISTIC600_USERS_JSON index for perfloadNN (anchor = 0)."""
    local = email.split("@", 1)[0]
    if "+perfload" not in local:
        raise ValueError(f"not a perfload email: {email}")
    num = int(local.rsplit("perfload", 1)[1])
    if num < 51 or num > 83:
        raise ValueError(f"email outside allowlist 51–83: {email}")
    return num - 1  # perfload51 -> slot 50


def http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str],
    body: dict | None = None,
) -> tuple[int, dict | list | str, dict[str, str]]:
    data = None
    if body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    resp_headers: dict[str, str] = {}
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            resp_headers = {k.lower(): v for k, v in resp.headers.items()}
            raw = resp.read().decode()
            if not raw:
                return resp.status, {}, resp_headers
            try:
                return resp.status, json.loads(raw), resp_headers
            except json.JSONDecodeError:
                return resp.status, raw, resp_headers
    except urllib.error.HTTPError as e:
        resp_headers = {k.lower(): v for k, v in (e.headers.items() if e.headers else [])}
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw), resp_headers
        except json.JSONDecodeError:
            return e.code, raw, resp_headers


def parse_retry_after_seconds(headers: dict[str, str]) -> float | None:
    raw = headers.get("retry-after")
    if not raw:
        return None
    raw = raw.strip()
    try:
        sec = float(raw)
        if sec >= 0:
            return sec
    except ValueError:
        pass
    try:
        from email.utils import parsedate_to_datetime

        dt = parsedate_to_datetime(raw)
        if dt.tzinfo is None:
            import datetime as _dt

            dt = dt.replace(tzinfo=_dt.timezone.utc)
        return max(0.0, dt.timestamp() - time.time())
    except (TypeError, ValueError, OverflowError):
        return None


def auth_backoff_seconds(attempt: int, retry_after: float | None) -> float:
    if retry_after is not None:
        return min(60.0, retry_after + random.uniform(0, 0.25))
    base = min(60.0, 0.8 * (2**attempt))
    return min(60.0, base + random.uniform(0, base * 0.25))


def admin_request_with_retry(
    method: str,
    url: str,
    *,
    service_role: str,
    body: dict | None = None,
    label: str,
) -> tuple[int, dict | list | str, dict[str, str]]:
    headers = {
        "apikey": service_role,
        "Authorization": f"Bearer {service_role}",
        "Content-Type": "application/json",
    }
    attempt = 0
    while True:
        status, payload, resp_headers = http_json(method, url, headers=headers, body=body)
        if status != 429 or attempt >= AUTH_MAX_RETRIES:
            return status, payload, resp_headers
        attempt += 1
        wait = auth_backoff_seconds(attempt, parse_retry_after_seconds(resp_headers))
        hint = " (Retry-After)" if parse_retry_after_seconds(resp_headers) is not None else ""
        print(f"  {label} HTTP 429 — retry {attempt}/{AUTH_MAX_RETRIES} in {wait:.1f}s{hint}")
        time.sleep(wait)


def list_admin_users_page(base: str, service_role: str, page: int, per_page: int = 1000) -> list[dict]:
    q = urllib.parse.urlencode({"page": page, "per_page": per_page})
    status, payload, _ = admin_request_with_retry(
        "GET",
        f"{base}/auth/v1/admin/users?{q}",
        service_role=service_role,
        label=f"admin listUsers page={page}",
    )
    if status != 200 or not isinstance(payload, dict):
        raise RuntimeError(f"admin listUsers HTTP {status}: {payload}")
    users = payload.get("users")
    if not isinstance(users, list):
        return []
    return users


def resolve_allowlisted_auth_users(base: str, service_role: str, emails: list[str]) -> dict[str, dict]:
    """email (lower) -> {id, email, ...} for allowlisted perfload51–83 only."""
    want = {e.lower() for e in emails}
    found: dict[str, dict] = {}
    page = 1
    while want - set(found.keys()):
        rows = list_admin_users_page(base, service_role, page)
        if not rows:
            break
        for u in rows:
            em = (u.get("email") or "").strip().lower()
            if em in want and em not in found:
                found[em] = u
        if len(rows) < 1000:
            break
        page += 1
        time.sleep(0.3)
    return found


def admin_update_password(base: str, service_role: str, user_id: str, password: str, email: str) -> None:
    status, payload, _ = admin_request_with_retry(
        "PUT",
        f"{base}/auth/v1/admin/users/{user_id}",
        service_role=service_role,
        body={"password": password},
        label=f"admin updateUser {email}",
    )
    if status != 200:
        raise RuntimeError(f"admin updateUser HTTP {status}: {payload}")


def password_grant_verify(base: str, anon: str, email: str, password: str) -> str:
    """Returns access_token on success."""
    prov = load_provision_module()
    token, err = prov.login_with_retry(base, anon, email, password)
    if err or not token:
        raise RuntimeError(f"password grant failed: {err}")
    return token


def load_recovery_state() -> dict:
    if not RECOVERY_FILE.is_file():
        return {"schema_version": RECOVERY_SCHEMA_VERSION, "project_ref": PRODUCTION_PROJECT_REF, "accounts": {}}
    data = json.loads(RECOVERY_FILE.read_text())
    if not isinstance(data, dict):
        raise RuntimeError(f"invalid recovery file (not object): {RECOVERY_FILE}")
    accounts = data.get("accounts")
    if not isinstance(accounts, dict):
        accounts = {}
    for em in list(accounts.keys()):
        if em.lower() not in {e.lower() for e in allowlisted_emails()}:
            raise RuntimeError(f"recovery file contains non-allowlisted email entry; refuse to continue")
    return {
        "schema_version": RECOVERY_SCHEMA_VERSION,
        "project_ref": data.get("project_ref") or PRODUCTION_PROJECT_REF,
        "accounts": accounts,
    }


def atomic_write_recovery(state: dict) -> None:
    RECOVERY_DIR.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, indent=2, sort_keys=True) + "\n"
    fd, tmp_path = tempfile.mkstemp(
        prefix=f"{RECOVERY_FILE.name}.",
        suffix=".tmp",
        dir=RECOVERY_DIR,
    )
    tmp = Path(tmp_path)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(payload)
        os.chmod(tmp, 0o600)
        os.replace(tmp, RECOVERY_FILE)
        os.chmod(RECOVERY_FILE, 0o600)
    finally:
        if tmp.is_file():
            tmp.unlink(missing_ok=True)


def merge_and_persist_env(prov, cfg: dict[str, str], recovery_accounts: dict) -> None:
    raw50 = json.loads(cfg.get("LOADTEST_USERS_JSON", "[]"))
    if not isinstance(raw50, list) or len(raw50) < ONEFIFTY_USER_COUNT:
        raise RuntimeError("LOADTEST_USERS_JSON must contain at least 50 users")

    users = prov.merge_realistic600_users(raw50, None, REALISTIC600_USER_COUNT)
    for email, entry in recovery_accounts.items():
        if not isinstance(entry, dict):
            continue
        pw = entry.get("password") or ""
        if not pw or not entry.get("password_grant_verified"):
            continue
        slot = entry.get("slot")
        if slot is None:
            slot = slot_for_email(email)
        if slot < ONEFIFTY_USER_COUNT or slot >= REALISTIC600_USER_COUNT:
            raise RuntimeError(f"invalid slot for {email}: {slot}")
        users[slot] = {"email": email, "password": pw}

    prov.write_users_json(ENV_FILE, users, "LOADTEST_REALISTIC600_USERS_JSON")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Admin password recovery for perfload51–83 (realistic600_full)."
    )
    p.add_argument(
        "--execute",
        action="store_true",
        help=f"Perform live Admin password updates (requires {EXECUTE_CONFIRM_ENV}=yes).",
    )
    p.add_argument(
        "--pace-sec",
        type=float,
        default=DEFAULT_PACE_SEC,
        help=f"Seconds between live Admin updates (default {DEFAULT_PACE_SEC}).",
    )
    p.add_argument(
        "--skip-env-merge",
        action="store_true",
        help="Do not update LOADTEST_REALISTIC600_USERS_JSON (recovery file only).",
    )
    return p.parse_args()


def assert_production_target(base: str, prov) -> None:
    cfg = prov.load_env(ENV_FILE)
    prov.assert_production_target(base, cfg)
    ref = cfg.get("TRADETRAXS_PRODUCTION_PROJECT_REF", "").strip()
    if ref and ref != PRODUCTION_PROJECT_REF:
        raise SystemExit(f"error: TRADETRAXS_PRODUCTION_PROJECT_REF must be {PRODUCTION_PROJECT_REF}")


def main() -> int:
    args = parse_args()
    dry_run = not args.execute

    if args.execute and os.environ.get(EXECUTE_CONFIRM_ENV, "").strip().lower() != "yes":
        print(
            f"error: --execute requires {EXECUTE_CONFIRM_ENV}=yes in the environment",
            file=sys.stderr,
        )
        return 1

    if not ENV_FILE.is_file():
        print(f"error: missing {ENV_FILE}", file=sys.stderr)
        return 1

    prov = load_provision_module()
    cfg = prov.load_env(ENV_FILE)
    base = cfg.get("LOADTEST_SUPABASE_URL", "").rstrip("/")
    anon = cfg.get("LOADTEST_SUPABASE_ANON_KEY", "")
    if not base or not anon:
        print("error: LOADTEST_SUPABASE_URL / LOADTEST_SUPABASE_ANON_KEY missing", file=sys.stderr)
        return 1
    assert_production_target(base, prov)

    try:
        service_role = assert_service_role_key(
            os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""),
            anon,
            base,
        )
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 1

    try:
        verify_admin_auth_read_access(base, service_role)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 1

    emails = allowlisted_emails()
    print(
        f"recover-realistic600: mode={'dry-run' if dry_run else 'execute'} "
        f"allowlist=perfload51-83 count={len(emails)} recovery_file={RECOVERY_FILE.relative_to(ROOT)}"
    )

    auth_by_email = resolve_allowlisted_auth_users(base, service_role, emails)
    missing = [e for e in emails if e.lower() not in auth_by_email]
    for e in emails:
        row = auth_by_email.get(e.lower())
        if row:
            print(f"  auth: {e} id={row.get('id')}")
        else:
            print(f"  auth: {e} MISSING")

    if missing:
        print(f"error: {len(missing)} allowlisted users not found in Auth", file=sys.stderr)
        if not dry_run:
            return 1

    state = load_recovery_state()
    accounts: dict = state["accounts"]
    verified_in_file = sum(
        1
        for e in emails
        if accounts.get(e, {}).get("password_grant_verified")
        and accounts.get(e, {}).get("password")
    )
    print(f"recovery_file: verified_entries={verified_in_file}/{len(emails)}")

    if dry_run:
        pending = [e for e in emails if not accounts.get(e, {}).get("password_grant_verified")]
        print(f"dry-run: would_reset={len(pending)} already_verified_in_file={len(emails) - len(pending)}")
        print("dry-run: no Auth or env changes")
        return 0 if not missing else 1

    stats_reset = 0
    stats_skipped = 0
    stats_failed = 0

    for email in emails:
        entry = accounts.get(email) or {}
        if entry.get("password_grant_verified") and entry.get("password"):
            stats_skipped += 1
            print(f"skip: {email} (already verified in recovery file)")
            continue

        user = auth_by_email.get(email.lower())
        if not user or not user.get("id"):
            print(f"error: no Auth user for {email}", file=sys.stderr)
            stats_failed += 1
            break

        uid = str(user["id"])
        if args.pace_sec > 0:
            time.sleep(args.pace_sec)

        password = secrets.token_urlsafe(18)
        try:
            admin_update_password(base, service_role, uid, password, email)
            password_grant_verify(base, anon, email, password)
        except RuntimeError as exc:
            print(f"error: {email}: {exc}", file=sys.stderr)
            stats_failed += 1
            atomic_write_recovery(state)
            break

        slot = slot_for_email(email)
        accounts[email] = {
            "slot": slot,
            "user_id": uid,
            "password": password,
            "password_grant_verified": True,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }
        state["accounts"] = accounts
        atomic_write_recovery(state)
        stats_reset += 1
        print(f"ok: {email} slot={slot} id={uid} password_grant=verified")

        if not args.skip_env_merge:
            merge_and_persist_env(prov, cfg, accounts)

    verified = sum(
        1
        for e in emails
        if accounts.get(e, {}).get("password_grant_verified") and accounts.get(e, {}).get("password")
    )
    print(
        f"summary: reset={stats_reset} skipped={stats_skipped} failed={stats_failed} "
        f"verified_in_file={verified}/{len(emails)}"
    )

    if not args.skip_env_merge and verified > 0:
        filled = ONEFIFTY_USER_COUNT + verified
        print(
            f"env: LOADTEST_REALISTIC600_USERS_JSON updated ({filled} non-placeholder slots "
            f"including 50 base + {verified} recovered; perfload84-100 remain placeholders)"
        )

    if stats_failed:
        return 1
    if verified < len(emails):
        print("incomplete: re-run --execute to resume", file=sys.stderr)
        return 1

    print("ok: all 33 perfload51–83 recovered; ready for provision-prod-perf-accounts.py --realistic600")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
