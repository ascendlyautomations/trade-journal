#!/usr/bin/env python3
"""
Provision dedicated prod perf auth accounts + varied follow graphs (RLS-safe).

- Auth: Supabase /auth/v1/signup + password grant (anon key only).
- Follows: PostgREST on public.followers with each user JWT (insert + delete sync).
- Does NOT call /api/notifications/follow.
- Does NOT use service_role or SQL DDL.

Updates loadtest/.env.production-perf LOADTEST_USERS_JSON in place.

Usage:
  python3 loadtest/scripts/provision-prod-perf-accounts.py
      # (legacy) ensure 30 slots: anchor + perfload02..30

  python3 loadtest/scripts/provision-prod-perf-accounts.py --onefifty
      # extend to 50: keep users[0..29], create perfload31..50, follow-sync new slots only

  python3 loadtest/scripts/provision-prod-perf-accounts.py --realistic600
      # extend to 100: keep users[0..49], create perfload51..100; writes LOADTEST_REALISTIC600_USERS_JSON
      # Resumable: merges partial LOADTEST_REALISTIC600_USERS_JSON, persists env after each signup.

  TRADETRAXS_PERF_AUTH_SIGNUP_SPACING_SEC=3  (default 3s between signups; --signup-spacing)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import re
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / "loadtest" / ".env.production-perf"

TARGET_USER_COUNT = 30
ONEFIFTY_USER_COUNT = 50
REALISTIC600_USER_COUNT = 100
PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"
# users[0] anchor; users[1] = perfload02; users[30] = perfload31
ONEFIFTY_NEW_SLOT_START = 30
REALISTIC600_NEW_SLOT_START = 50
DEFAULT_SIGNUP_SPACING_SEC = 3.0
AUTH_MAX_RETRIES = 12

# Public active profiles (read-only audit 2026-10-27); excludes tradetraxs_demo perf anchor.
FOLLOW_TARGET_POOL = [
    "d3aeace4-e2a5-4679-b47d-23d40d6e2c59",
    "e432738b-47bd-439b-a669-c71082202895",
    "e30ffa08-bf5b-47f5-b5b3-1de7259a0bf5",
    "70d205c1-f95f-4037-a959-ba98ae879fbb",
    "9459ae37-f543-424b-9782-181ea5af54a4",
    "8f8a8f03-7595-4975-b4e8-7bf262c2e85a",
    "9cdf5d06-8d08-4d56-a4b1-1c4a2ed9e575",
    "33d8a85d-c934-4da9-a250-5439daa95fb2",
    "35bc24e4-5eac-4451-bc73-6e5a172a54bf",
    "e9dc6303-542e-4945-bf52-891a380c48b5",
    "e57ffb8f-e16f-4f64-8f10-018405cf2f97",
    "ed13279a-1a64-4810-81b0-abfff1d8b234",
    "93210f21-d9da-4da6-89e0-99b997b26b40",
    "8dda95a0-6657-410f-98c9-7848d6f1a98f",
    "186790e0-a5dd-4336-b567-58e7945d0f5e",
    "5ef00b6d-e62a-4554-8168-db7d1f57dd7e",
    "27de3b80-f9f1-466c-ac38-a81465b19099",
    "26dd89f0-febb-43a4-8620-5785e7e1e20e",
    "5b876f35-6e93-4805-83ef-639baccc728a",
    "a5c013b5-7dad-41d3-ae70-5b4662e044ef",
    "0be6442c-07fe-404f-9948-3d7a836c7f26",
    "2fff78ee-c4c8-4ce3-a8ff-066eb1329e7c",
    "bb4920b0-5488-4040-b403-ed4ea9e42353",
    "0e4fcdd8-1144-47d7-bcac-8c5017e20230",
    "22dc1d6c-177d-4051-9852-7c837857ccfa",
    "ac0c5dd9-6ce5-4d61-aa73-e25d5ed040e2",
    "ff8bcc72-6442-4360-b037-9780d72fb19b",
    "8bb26d91-b548-4f7a-a66b-67840d04671b",
    "6d0c4bd9-cee9-44e6-a7d9-240f2d59d4a4",
]

NEW_ACCOUNT_SPECS = [
    ("tradetraxsdemo+perfload02@gmail.com", "TradeTraxs Perf Load 02"),
    ("tradetraxsdemo+perfload03@gmail.com", "TradeTraxs Perf Load 03"),
    ("tradetraxsdemo+perfload04@gmail.com", "TradeTraxs Perf Load 04"),
    ("tradetraxsdemo+perfload05@gmail.com", "TradeTraxs Perf Load 05"),
    ("tradetraxsdemo+perfload06@gmail.com", "TradeTraxs Perf Load 06"),
    ("tradetraxsdemo+perfload07@gmail.com", "TradeTraxs Perf Load 07"),
    ("tradetraxsdemo+perfload08@gmail.com", "TradeTraxs Perf Load 08"),
    ("tradetraxsdemo+perfload09@gmail.com", "TradeTraxs Perf Load 09"),
    ("tradetraxsdemo+perfload10@gmail.com", "TradeTraxs Perf Load 10"),
    ("tradetraxsdemo+perfload11@gmail.com", "TradeTraxs Perf Load 11"),
    ("tradetraxsdemo+perfload12@gmail.com", "TradeTraxs Perf Load 12"),
    ("tradetraxsdemo+perfload13@gmail.com", "TradeTraxs Perf Load 13"),
    ("tradetraxsdemo+perfload14@gmail.com", "TradeTraxs Perf Load 14"),
    ("tradetraxsdemo+perfload15@gmail.com", "TradeTraxs Perf Load 15"),
    ("tradetraxsdemo+perfload16@gmail.com", "TradeTraxs Perf Load 16"),
    ("tradetraxsdemo+perfload17@gmail.com", "TradeTraxs Perf Load 17"),
    ("tradetraxsdemo+perfload18@gmail.com", "TradeTraxs Perf Load 18"),
    ("tradetraxsdemo+perfload19@gmail.com", "TradeTraxs Perf Load 19"),
    ("tradetraxsdemo+perfload20@gmail.com", "TradeTraxs Perf Load 20"),
    ("tradetraxsdemo+perfload21@gmail.com", "TradeTraxs Perf Load 21"),
    ("tradetraxsdemo+perfload22@gmail.com", "TradeTraxs Perf Load 22"),
    ("tradetraxsdemo+perfload23@gmail.com", "TradeTraxs Perf Load 23"),
    ("tradetraxsdemo+perfload24@gmail.com", "TradeTraxs Perf Load 24"),
    ("tradetraxsdemo+perfload25@gmail.com", "TradeTraxs Perf Load 25"),
    ("tradetraxsdemo+perfload26@gmail.com", "TradeTraxs Perf Load 26"),
    ("tradetraxsdemo+perfload27@gmail.com", "TradeTraxs Perf Load 27"),
    ("tradetraxsdemo+perfload28@gmail.com", "TradeTraxs Perf Load 28"),
    ("tradetraxsdemo+perfload29@gmail.com", "TradeTraxs Perf Load 29"),
    ("tradetraxsdemo+perfload30@gmail.com", "TradeTraxs Perf Load 30"),
    ("tradetraxsdemo+perfload31@gmail.com", "TradeTraxs Perf Load 31"),
    ("tradetraxsdemo+perfload32@gmail.com", "TradeTraxs Perf Load 32"),
    ("tradetraxsdemo+perfload33@gmail.com", "TradeTraxs Perf Load 33"),
    ("tradetraxsdemo+perfload34@gmail.com", "TradeTraxs Perf Load 34"),
    ("tradetraxsdemo+perfload35@gmail.com", "TradeTraxs Perf Load 35"),
    ("tradetraxsdemo+perfload36@gmail.com", "TradeTraxs Perf Load 36"),
    ("tradetraxsdemo+perfload37@gmail.com", "TradeTraxs Perf Load 37"),
    ("tradetraxsdemo+perfload38@gmail.com", "TradeTraxs Perf Load 38"),
    ("tradetraxsdemo+perfload39@gmail.com", "TradeTraxs Perf Load 39"),
    ("tradetraxsdemo+perfload40@gmail.com", "TradeTraxs Perf Load 40"),
    ("tradetraxsdemo+perfload41@gmail.com", "TradeTraxs Perf Load 41"),
    ("tradetraxsdemo+perfload42@gmail.com", "TradeTraxs Perf Load 42"),
    ("tradetraxsdemo+perfload43@gmail.com", "TradeTraxs Perf Load 43"),
    ("tradetraxsdemo+perfload44@gmail.com", "TradeTraxs Perf Load 44"),
    ("tradetraxsdemo+perfload45@gmail.com", "TradeTraxs Perf Load 45"),
    ("tradetraxsdemo+perfload46@gmail.com", "TradeTraxs Perf Load 46"),
    ("tradetraxsdemo+perfload47@gmail.com", "TradeTraxs Perf Load 47"),
    ("tradetraxsdemo+perfload48@gmail.com", "TradeTraxs Perf Load 48"),
    ("tradetraxsdemo+perfload49@gmail.com", "TradeTraxs Perf Load 49"),
    ("tradetraxsdemo+perfload50@gmail.com", "TradeTraxs Perf Load 50"),
    ("tradetraxsdemo+perfload51@gmail.com", "TradeTraxs Perf Load 51"),
    ("tradetraxsdemo+perfload52@gmail.com", "TradeTraxs Perf Load 52"),
    ("tradetraxsdemo+perfload53@gmail.com", "TradeTraxs Perf Load 53"),
    ("tradetraxsdemo+perfload54@gmail.com", "TradeTraxs Perf Load 54"),
    ("tradetraxsdemo+perfload55@gmail.com", "TradeTraxs Perf Load 55"),
    ("tradetraxsdemo+perfload56@gmail.com", "TradeTraxs Perf Load 56"),
    ("tradetraxsdemo+perfload57@gmail.com", "TradeTraxs Perf Load 57"),
    ("tradetraxsdemo+perfload58@gmail.com", "TradeTraxs Perf Load 58"),
    ("tradetraxsdemo+perfload59@gmail.com", "TradeTraxs Perf Load 59"),
    ("tradetraxsdemo+perfload60@gmail.com", "TradeTraxs Perf Load 60"),
    ("tradetraxsdemo+perfload61@gmail.com", "TradeTraxs Perf Load 61"),
    ("tradetraxsdemo+perfload62@gmail.com", "TradeTraxs Perf Load 62"),
    ("tradetraxsdemo+perfload63@gmail.com", "TradeTraxs Perf Load 63"),
    ("tradetraxsdemo+perfload64@gmail.com", "TradeTraxs Perf Load 64"),
    ("tradetraxsdemo+perfload65@gmail.com", "TradeTraxs Perf Load 65"),
    ("tradetraxsdemo+perfload66@gmail.com", "TradeTraxs Perf Load 66"),
    ("tradetraxsdemo+perfload67@gmail.com", "TradeTraxs Perf Load 67"),
    ("tradetraxsdemo+perfload68@gmail.com", "TradeTraxs Perf Load 68"),
    ("tradetraxsdemo+perfload69@gmail.com", "TradeTraxs Perf Load 69"),
    ("tradetraxsdemo+perfload70@gmail.com", "TradeTraxs Perf Load 70"),
    ("tradetraxsdemo+perfload71@gmail.com", "TradeTraxs Perf Load 71"),
    ("tradetraxsdemo+perfload72@gmail.com", "TradeTraxs Perf Load 72"),
    ("tradetraxsdemo+perfload73@gmail.com", "TradeTraxs Perf Load 73"),
    ("tradetraxsdemo+perfload74@gmail.com", "TradeTraxs Perf Load 74"),
    ("tradetraxsdemo+perfload75@gmail.com", "TradeTraxs Perf Load 75"),
    ("tradetraxsdemo+perfload76@gmail.com", "TradeTraxs Perf Load 76"),
    ("tradetraxsdemo+perfload77@gmail.com", "TradeTraxs Perf Load 77"),
    ("tradetraxsdemo+perfload78@gmail.com", "TradeTraxs Perf Load 78"),
    ("tradetraxsdemo+perfload79@gmail.com", "TradeTraxs Perf Load 79"),
    ("tradetraxsdemo+perfload80@gmail.com", "TradeTraxs Perf Load 80"),
    ("tradetraxsdemo+perfload81@gmail.com", "TradeTraxs Perf Load 81"),
    ("tradetraxsdemo+perfload82@gmail.com", "TradeTraxs Perf Load 82"),
    ("tradetraxsdemo+perfload83@gmail.com", "TradeTraxs Perf Load 83"),
    ("tradetraxsdemo+perfload84@gmail.com", "TradeTraxs Perf Load 84"),
    ("tradetraxsdemo+perfload85@gmail.com", "TradeTraxs Perf Load 85"),
    ("tradetraxsdemo+perfload86@gmail.com", "TradeTraxs Perf Load 86"),
    ("tradetraxsdemo+perfload87@gmail.com", "TradeTraxs Perf Load 87"),
    ("tradetraxsdemo+perfload88@gmail.com", "TradeTraxs Perf Load 88"),
    ("tradetraxsdemo+perfload89@gmail.com", "TradeTraxs Perf Load 89"),
    ("tradetraxsdemo+perfload90@gmail.com", "TradeTraxs Perf Load 90"),
    ("tradetraxsdemo+perfload91@gmail.com", "TradeTraxs Perf Load 91"),
    ("tradetraxsdemo+perfload92@gmail.com", "TradeTraxs Perf Load 92"),
    ("tradetraxsdemo+perfload93@gmail.com", "TradeTraxs Perf Load 93"),
    ("tradetraxsdemo+perfload94@gmail.com", "TradeTraxs Perf Load 94"),
    ("tradetraxsdemo+perfload95@gmail.com", "TradeTraxs Perf Load 95"),
    ("tradetraxsdemo+perfload96@gmail.com", "TradeTraxs Perf Load 96"),
    ("tradetraxsdemo+perfload97@gmail.com", "TradeTraxs Perf Load 97"),
    ("tradetraxsdemo+perfload98@gmail.com", "TradeTraxs Perf Load 98"),
    ("tradetraxsdemo+perfload99@gmail.com", "TradeTraxs Perf Load 99"),
    ("tradetraxsdemo+perfload100@gmail.com", "TradeTraxs Perf Load 100"),
]


def load_env(path: Path) -> dict[str, str]:
    cfg: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in ("'", '"'):
            v = v[1:-1]
        cfg[k.strip()] = v
    return cfg


def write_users_json(path: Path, users: list[dict], env_key: str = "LOADTEST_USERS_JSON") -> None:
    text = path.read_text()
    payload = json.dumps(users, separators=(",", ":"))
    new_line = f"{env_key}='{payload}'"
    pattern = re.escape(env_key) + r"='.*'"
    if not re.search(pattern, text, flags=re.DOTALL):
        text = text.rstrip() + "\n" + new_line + "\n"
    else:
        text = re.sub(pattern, new_line, text, count=1, flags=re.DOTALL)
    path.write_text(text)


def http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str],
    body: dict | list | None = None,
) -> tuple[int, dict | list | str, dict[str, str]]:
    data = None
    if body is not None:
        data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    resp_headers: dict[str, str] = {}
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
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
        wait = (dt.timestamp() - time.time())
        return max(0.0, wait)
    except (TypeError, ValueError, OverflowError):
        return None


def auth_backoff_seconds(attempt: int, retry_after: float | None) -> float:
    if retry_after is not None:
        return min(60.0, retry_after + random.uniform(0, 0.25))
    base = min(60.0, 0.8 * (2**attempt))
    return min(60.0, base + random.uniform(0, base * 0.25))


def auth_post_with_retry(
    url: str,
    *,
    headers: dict[str, str],
    body: dict,
    label: str,
    max_retries: int = AUTH_MAX_RETRIES,
) -> tuple[int, dict | list | str, dict[str, str]]:
    attempt = 0
    while True:
        status, payload, resp_headers = http_json("POST", url, headers=headers, body=body)
        if status != 429 or attempt >= max_retries:
            return status, payload, resp_headers
        attempt += 1
        wait = auth_backoff_seconds(attempt, parse_retry_after_seconds(resp_headers))
        hint = " (Retry-After)" if parse_retry_after_seconds(resp_headers) is not None else ""
        print(f"  {label} HTTP 429 — retry {attempt}/{max_retries} in {wait:.1f}s{hint}")
        time.sleep(wait)


def signup_already_registered(status: int, payload: dict | list | str) -> bool:
    if status not in (400, 422):
        return False
    text = json.dumps(payload) if isinstance(payload, (dict, list)) else str(payload)
    lower = text.lower()
    return "already registered" in lower or "already been registered" in lower or "user already exists" in lower


def signup(base: str, anon: str, email: str, password: str, name: str) -> tuple[str | None, str | None]:
    status, payload, _ = auth_post_with_retry(
        f"{base}/auth/v1/signup",
        headers={"apikey": anon, "Content-Type": "application/json"},
        body={
            "email": email,
            "password": password,
            "data": {"name": name, "signup_flow_source": "standard_email"},
        },
        label=f"signup {email}",
    )
    if status not in (200, 201):
        if signup_already_registered(status, payload):
            return None, "signup_user_already_registered"
        return None, f"signup HTTP {status}: {payload}"

    if not isinstance(payload, dict):
        return None, "signup unexpected response"

    session = payload.get("session")
    if session and session.get("access_token"):
        return session["access_token"], None

    user = payload.get("user")
    if user and payload.get("confirmation_sent_at"):
        return None, "email_confirmation_required"

    if user:
        token, err = login_with_retry(base, anon, email, password)
        return token, err

    return None, "signup_missing_session"


def login(base: str, anon: str, email: str, password: str) -> tuple[str | None, str | None]:
    status, payload, _ = auth_post_with_retry(
        f"{base}/auth/v1/token?grant_type=password",
        headers={"apikey": anon, "Content-Type": "application/json"},
        body={"email": email, "password": password},
        label=f"login {email}",
    )
    if status != 200 or not isinstance(payload, dict) or not payload.get("access_token"):
        return None, f"login HTTP {status}: {payload}"
    return payload["access_token"], None


def user_id_from_jwt(token: str) -> str:
    import base64

    part = token.split(".")[1]
    part += "=" * (-len(part) % 4)
    data = json.loads(base64.urlsafe_b64decode(part.encode()))
    sub = data.get("sub")
    if not sub:
        raise RuntimeError("JWT missing sub")
    return str(sub)


def ensure_profile_row(base: str, anon: str, token: str, uid: str) -> None:
    headers = {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    status, rows, _ = http_json(
        "GET",
        f"{base}/rest/v1/profiles?id=eq.{uid}&select=id",
        headers=headers,
    )
    if status == 200 and isinstance(rows, list) and len(rows) > 0:
        return
    status, err, _ = http_json(
        "POST",
        f"{base}/rest/v1/profiles",
        headers={**headers, "Prefer": "return=minimal"},
        body={
            "id": uid,
            "name": "TradeTraxs Load Test",
            "is_pro": True,
            "subscription_status": "inactive",
        },
    )
    if status not in (200, 201, 204):
        raise RuntimeError(f"profile ensure failed HTTP {status}: {err}")


def follow_set_for_user_index(user_index: int, exclude_uid: str) -> list[str]:
    """Deterministic 10–20 public follows; varies by account index."""
    pool = [tid for tid in FOLLOW_TARGET_POOL if tid != exclude_uid]
    digest = hashlib.sha256(f"perf-follow-v1:{user_index}".encode()).digest()
    rng = random.Random(int.from_bytes(digest[:8], "big"))
    size = 10 + (user_index * 3 + digest[8]) % 11  # 10..20 inclusive
    shuffled = pool.copy()
    rng.shuffle(shuffled)
    # Rotate start so adjacent indices do not share identical prefixes.
    start = (user_index * 5) % len(shuffled)
    ordered = shuffled[start:] + shuffled[:start]
    return ordered[:size]


def list_following_ids(base: str, anon: str, token: str, uid: str) -> set[str]:
    headers = {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
    }
    status, rows, _ = http_json(
        "GET",
        f"{base}/rest/v1/followers?follower_id=eq.{uid}&select=following_id",
        headers=headers,
    )
    if status != 200 or not isinstance(rows, list):
        raise RuntimeError(f"followers list HTTP {status}: {rows}")
    return {str(r["following_id"]) for r in rows if r.get("following_id")}


def sync_follows(base: str, anon: str, token: str, uid: str, target_ids: list[str]) -> tuple[int, int]:
    """Insert missing follows; remove follows outside target (no notify API)."""
    headers = {
        "apikey": anon,
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    target = {tid for tid in target_ids if tid != uid}
    current = list_following_ids(base, anon, token, uid)
    to_remove = current - target
    to_add = target - current

    removed = 0
    for fid in to_remove:
        q = urllib.parse.urlencode(
            {"follower_id": f"eq.{uid}", "following_id": f"eq.{fid}"},
            safe=".",
        )
        status, err, _ = http_json(
            "DELETE",
            f"{base}/rest/v1/followers?{q}",
            headers=headers,
        )
        if status not in (200, 204):
            raise RuntimeError(f"unfollow HTTP {status}: {err}")
        removed += 1

    inserted = 0
    if to_add:
        rows = [{"follower_id": uid, "following_id": tid} for tid in sorted(to_add)]
        status, err, _ = http_json(
            "POST",
            f"{base}/rest/v1/followers",
            headers={**headers, "Prefer": "resolution=ignore-duplicates,return=minimal"},
            body=rows,
        )
        if status in (200, 201, 204):
            inserted = len(rows)
        elif status == 409:
            for row in rows:
                st, _, _ = http_json(
                    "POST",
                    f"{base}/rest/v1/followers",
                    headers={**headers, "Prefer": "resolution=ignore-duplicates,return=minimal"},
                    body=row,
                )
                if st in (200, 201, 204, 409):
                    inserted += 1
        else:
            raise RuntimeError(f"followers insert HTTP {status}: {err}")

    return inserted, removed


def is_placeholder(u: dict) -> bool:
    email = (u.get("email") or "").strip()
    password = u.get("password") or ""
    if email.startswith("REPLACE_WITH_") or password.startswith("REPLACE_WITH_"):
        return True
    if email == "REPLACE_WITH_PERF_EMAIL" or password == "REPLACE_WITH_PERF_PASSWORD":
        return True
    return not email or not password


def pad_users(users: list[dict], target: int) -> list[dict]:
    out = list(users)
    while len(out) < target:
        out.append({"email": "REPLACE_WITH_PERF_EMAIL", "password": "REPLACE_WITH_PERF_PASSWORD"})
    return out[:target]


def merge_realistic600_users(base50: list[dict], partial600: list[dict] | None, target: int) -> list[dict]:
    """Anchor + perfload02..50 from LOADTEST_USERS_JSON; overlay slots 50..99 from partial 600 JSON."""
    users = pad_users(list(base50[:ONEFIFTY_USER_COUNT]), target)
    if not partial600:
        return users
    for i in range(ONEFIFTY_USER_COUNT, min(len(partial600), target)):
        if not is_placeholder(partial600[i]):
            users[i] = {
                "email": (partial600[i].get("email") or "").strip(),
                "password": partial600[i].get("password") or "",
            }
    return users


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Provision prod perf test accounts (anon + PostgREST only).")
    p.add_argument(
        "--onefifty",
        action="store_true",
        help=f"Extend to {ONEFIFTY_USER_COUNT} users (perfload31..50); skip signup/follow resync for filled slots 0..29.",
    )
    p.add_argument(
        "--realistic600",
        action="store_true",
        help=f"Extend to {REALISTIC600_USER_COUNT} users (perfload51..100); writes LOADTEST_REALISTIC600_USERS_JSON; preserves slots 0..49.",
    )
    p.add_argument(
        "--target",
        type=int,
        default=None,
        help=f"Total LOADTEST_USERS_JSON entries (default {TARGET_USER_COUNT}, or {ONEFIFTY_USER_COUNT} with --onefifty).",
    )
    p.add_argument(
        "--signup-spacing",
        type=float,
        default=None,
        help=f"Seconds to wait before each new Auth signup (default {DEFAULT_SIGNUP_SPACING_SEC}; "
        "env TRADETRAXS_PERF_AUTH_SIGNUP_SPACING_SEC).",
    )
    return p.parse_args()


def assert_production_target(base: str, cfg: dict[str, str]) -> None:
    ref = cfg.get("TRADETRAXS_PRODUCTION_PROJECT_REF", "").strip()
    if ref and ref != PRODUCTION_PROJECT_REF:
        raise SystemExit(f"error: TRADETRAXS_PRODUCTION_PROJECT_REF must be {PRODUCTION_PROJECT_REF}")
    if PRODUCTION_PROJECT_REF not in base:
        raise SystemExit(f"error: LOADTEST_SUPABASE_URL must be production ref {PRODUCTION_PROJECT_REF}")


def login_with_retry(base: str, anon: str, email: str, password: str) -> tuple[str | None, str | None]:
    return login(base, anon, email, password)


def resolve_signup_spacing_sec(args: argparse.Namespace) -> float:
    if args.signup_spacing is not None:
        return max(0.0, float(args.signup_spacing))
    raw = os.environ.get("TRADETRAXS_PERF_AUTH_SIGNUP_SPACING_SEC", "").strip()
    if raw:
        try:
            return max(0.0, float(raw))
        except ValueError:
            pass
    return DEFAULT_SIGNUP_SPACING_SEC


def main() -> int:
    args = parse_args()
    if args.onefifty and args.realistic600:
        print("error: use only one of --onefifty or --realistic600", file=sys.stderr)
        return 1
    target = args.target or (
        REALISTIC600_USER_COUNT
        if args.realistic600
        else (ONEFIFTY_USER_COUNT if args.onefifty else TARGET_USER_COUNT)
    )
    extend_onefifty = args.onefifty
    extend_realistic600 = args.realistic600
    users_env_key = "LOADTEST_REALISTIC600_USERS_JSON" if extend_realistic600 else "LOADTEST_USERS_JSON"
    preserve_slot_start = (
        REALISTIC600_NEW_SLOT_START
        if extend_realistic600
        else (ONEFIFTY_NEW_SLOT_START if extend_onefifty else 0)
    )
    if extend_onefifty and target != ONEFIFTY_USER_COUNT:
        print("error: --onefifty requires target 50 (omit --target or pass --target 50)", file=sys.stderr)
        return 1
    if extend_realistic600 and target != REALISTIC600_USER_COUNT:
        print("error: --realistic600 requires target 100 (omit --target or pass --target 100)", file=sys.stderr)
        return 1
    if target < 1 or target > len(NEW_ACCOUNT_SPECS) + 1:
        print(
            f"error: target must be 1..{len(NEW_ACCOUNT_SPECS) + 1} (anchor + perfload02..100)",
            file=sys.stderr,
        )
        return 1

    if not ENV_FILE.is_file():
        print(f"error: missing {ENV_FILE}", file=sys.stderr)
        return 1

    cfg = load_env(ENV_FILE)
    base = cfg.get("LOADTEST_SUPABASE_URL", "").rstrip("/")
    anon = cfg.get("LOADTEST_SUPABASE_ANON_KEY", "")
    if not base or not anon:
        print("error: LOADTEST_SUPABASE_URL / ANON_KEY missing", file=sys.stderr)
        return 1
    assert_production_target(base, cfg)

    signup_spacing_sec = resolve_signup_spacing_sec(args)

    if extend_realistic600:
        raw_users = json.loads(cfg.get("LOADTEST_USERS_JSON", "[]"))
        if len(raw_users) < ONEFIFTY_USER_COUNT:
            print(
                "error: --realistic600 requires existing 50-user LOADTEST_USERS_JSON; run --onefifty first",
                file=sys.stderr,
            )
            return 1
        partial600: list[dict] | None = None
        raw600_text = cfg.get("LOADTEST_REALISTIC600_USERS_JSON", "").strip()
        if raw600_text:
            parsed = json.loads(raw600_text)
            if isinstance(parsed, list):
                partial600 = parsed
        users = merge_realistic600_users(raw_users, partial600, target)
    else:
        raw_users = json.loads(cfg.get("LOADTEST_USERS_JSON", "[]"))
        if not isinstance(raw_users, list) or len(raw_users) == 0:
            print("error: LOADTEST_USERS_JSON must be a non-empty array", file=sys.stderr)
            return 1
        users = pad_users(raw_users, target)
    if len(users) != target:
        print(f"error: internal user list must be {target}", file=sys.stderr)
        return 1

    pending_confirmation: list[str] = []
    initial_filled = frozenset(i for i in range(target) if not is_placeholder(users[i]))
    stats_created = 0
    stats_skipped = 0
    stats_failed = 0
    fatal_error = False

    print(
        f"provision: target={target} extend_onefifty={extend_onefifty} "
        f"extend_realistic600={extend_realistic600} env_key={users_env_key} "
        f"signup_spacing_sec={signup_spacing_sec} resumed_slots={len(initial_filled)}"
    )

    def persist_users() -> None:
        write_users_json(ENV_FILE, users, users_env_key)

    # Slot 0: anchor (tradetraxsdemo@gmail.com) — never sign up here.
    for slot in range(1, target):
        if preserve_slot_start and slot < preserve_slot_start and not is_placeholder(users[slot]):
            stats_skipped += 1
            print(f"user[{slot}]: skip signup (extend mode; existing account preserved)")
            continue

        spec_idx = slot - 1
        if spec_idx >= len(NEW_ACCOUNT_SPECS):
            break

        expected_email = NEW_ACCOUNT_SPECS[spec_idx][0]
        existing_email = (users[slot].get("email") or "").strip()
        if not is_placeholder(users[slot]):
            if existing_email and existing_email.lower() != expected_email.lower():
                print(
                    f"error: user[{slot}] email {existing_email!r} != expected {expected_email!r}",
                    file=sys.stderr,
                )
                stats_failed += 1
                fatal_error = True
                break
            stats_skipped += 1
            print(f"user[{slot}]: skip signup (reuse {existing_email})")
            continue

        email, name = NEW_ACCOUNT_SPECS[spec_idx]
        if signup_spacing_sec > 0:
            time.sleep(signup_spacing_sec)

        password = secrets.token_urlsafe(18)
        token, err = signup(base, anon, email, password, name)
        if err == "signup_user_already_registered":
            token, login_err = login_with_retry(base, anon, email, password)
            if not token:
                print(
                    f"user[{slot}]: Auth user already exists for {email} but login failed: {login_err}. "
                    "Restore credentials into LOADTEST_REALISTIC600_USERS_JSON (resume) or remove the Auth user.",
                    file=sys.stderr,
                )
                stats_failed += 1
                fatal_error = True
                persist_users()
                break
            err = None
        if err == "email_confirmation_required":
            pending_confirmation.append(email)
            users[slot] = {"email": email, "password": password}
            persist_users()
            stats_created += 1
            print(f"user[{slot}]: signup pending email confirmation for {email}")
            continue
        if err or not token:
            print(f"user[{slot}]: signup failed: {err}", file=sys.stderr)
            stats_failed += 1
            fatal_error = True
            persist_users()
            break

        uid = user_id_from_jwt(token)
        ensure_profile_row(base, anon, token, uid)
        target_follows = follow_set_for_user_index(slot, uid)
        ins, rem = sync_follows(base, anon, token, uid, target_follows)
        users[slot] = {"email": email, "password": password}
        persist_users()
        stats_created += 1
        print(
            f"user[{slot}]: created {email} uid={uid} "
            f"follows_target={len(target_follows)} inserted={ins} removed={rem}"
        )

    persist_users()

    for i, u in enumerate(users):
        if is_placeholder(u):
            continue
        if i in initial_filled:
            print(f"user[{i}]: skip follow resync (existing account at start)")
            continue
        if preserve_slot_start and i < preserve_slot_start:
            print(f"user[{i}]: skip follow resync (extend mode; preserve existing graph)")
            continue

        email = u["email"].strip()
        password = u["password"]
        token, err = login_with_retry(base, anon, email, password)
        if err or not token:
            print(f"user[{i}]: login failed for follow sync: {err}", file=sys.stderr)
            if email in pending_confirmation:
                continue
            stats_failed += 1
            fatal_error = True
            continue
        uid = user_id_from_jwt(token)
        ensure_profile_row(base, anon, token, uid)
        target_follows = follow_set_for_user_index(i, uid)
        ins, rem = sync_follows(base, anon, token, uid, target_follows)
        print(
            f"user[{i}]: follows_target={len(target_follows)} inserted={ins} removed={rem} "
            f"({email.split('@')[0][:12]}***)"
        )

    print(
        f"summary: created={stats_created} skipped={stats_skipped} failed={stats_failed} "
        f"filled={sum(1 for u in users if not is_placeholder(u))}/{target}"
    )

    if pending_confirmation:
        print("\nMANUAL: Confirm these emails before re-running preflight:", file=sys.stderr)
        for em in pending_confirmation:
            print(f"  - {em}", file=sys.stderr)
        return 2

    if fatal_error or stats_failed:
        print("error: provisioning incomplete (credentials persisted for completed slots)", file=sys.stderr)
        return 1

    if any(is_placeholder(u) for u in users):
        print("error: user list still has placeholders after provision", file=sys.stderr)
        return 1

    print(f"ok: {target} perf accounts; credentials in loadtest/.env.production-perf")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
