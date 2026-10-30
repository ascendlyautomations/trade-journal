#!/usr/bin/env python3
"""
One-time production fixture for realistic600_full (100 perf accounts only).

Creates (idempotent):
  - 50× private 1:1 DM shells (no messages — no notify-dm)
  - 1× perf-isolated trade room (unlisted open-join; see ROOM VISIBILITY below)
  - loadtest/fixtures/realistic300-full-isolation.json

Uses anon key + perf JWTs only (same auth paths as the app). Does NOT call
/api/messaging/notify-dm, /api/notifications/*, or insert messages.

ROOM VISIBILITY (schema/RLS):
  Private rooms cannot use join-request RPC (room_not_requestable). Open rooms
  use the same self-insert as iOS DefaultRoomRepository.join / web joinTradeRoom.
  room_members_insert_self requires the joiner to SELECT the rooms row (invoker
  RLS). With show_on_profile=false, non-members cannot read the room, so INSERT
  fails 42501 — see room_members_enable_rls migration notes. The script sets
  show_on_profile=true (owner PATCH, idempotent) so rooms_select_profile_public
  applies; join_policy=open, is_private=false; no notify APIs.

ROOM OWNERSHIP (schema):
  Each user may own at most one room (unique index on rooms.owner_user_id;
  rpc_v1_create_trade_room raises owned_room_exists / 23505). The script picks
  the first perf account in the spec member list that does not already own a room
  to create the loadtest room, or reuses an existing room only when the name
  matches the spec and every active member is a perf account.

Requires:
  LOADTEST_ENV=production
  TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes
  loadtest/.env.production-perf (LOADTEST_REALISTIC600_USERS_JSON — 100 users)

Usage:
  python3 loadtest/scripts/provision-realistic600-full-fixture.py --dry-run
  python3 loadtest/scripts/provision-realistic600-full-fixture.py
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import uuid
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / "loadtest" / ".env.production-perf"
SPEC_FILE = ROOT / "loadtest" / "fixtures" / "realistic600-full-isolation.email-spec.json"
OUT_FIXTURE = ROOT / "loadtest" / "fixtures" / "realistic600-full-isolation.json"
USERS_ENV_KEY = "LOADTEST_REALISTIC600_USERS_JSON"
EXPECTED_USER_COUNT = 100

PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"
AUTH_SPACING_SEC = 1.2
AUTH_MAX_RETRIES = 8
PERF_EMAIL_RE = re.compile(
    r"^(tradetraxsdemo@gmail\.com|tradetraxsdemo\+perfload(0[2-9]|[1-9][0-9]|100)@gmail\.com)$",
    re.I,
)


def load_env_file() -> dict[str, str]:
    if not ENV_FILE.is_file():
        sys.exit(f"error: missing {ENV_FILE}")
    env: dict[str, str] = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        v = v.strip()
        if (v.startswith("'") and v.endswith("'")) or (v.startswith('"') and v.endswith('"')):
            v = v[1:-1]
        env[k.strip()] = v
    return env


def http_json(method: str, url: str, headers: dict, body: dict | None = None) -> tuple[int, object]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    for k, v in headers.items():
        req.add_header(k, v)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            if not raw:
                return resp.status, None
            return resp.status, json.loads(raw)
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw[:500]}
        return e.code, payload


def password_grant(supabase_url: str, anon_key: str, email: str, password: str) -> dict:
    url = f"{supabase_url.rstrip('/')}/auth/v1/token?grant_type=password"
    attempt = 0
    while True:
        req = urllib.request.Request(
            url,
            data=json.dumps({"email": email, "password": password}).encode("utf-8"),
            method="POST",
            headers={"apikey": anon_key, "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                return {
                    "token": body["access_token"],
                    "user_id": body["user"]["id"],
                    "email": email,
                }
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8", errors="replace")
            if e.code == 429 and attempt < AUTH_MAX_RETRIES:
                attempt += 1
                retry_after = e.headers.get("Retry-After")
                if retry_after and str(retry_after).isdigit():
                    wait = int(retry_after) + 0.25
                else:
                    wait = min(60.0, 0.8 * (2**attempt) + (0.25 * attempt))
                print(f"  auth 429 {email} retry {attempt}/{AUTH_MAX_RETRIES} in {wait:.1f}s")
                time.sleep(wait)
                continue
            raise RuntimeError(f"auth failed for {email}: HTTP {e.code} {raw[:120]}")


def rest_headers(anon_key: str, token: str, prefer: str | None = None) -> dict:
    h = {
        "apikey": anon_key,
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    if prefer:
        h["Prefer"] = prefer
    return h


def assert_perf_email(email: str) -> str:
    e = email.strip().lower()
    if not PERF_EMAIL_RE.match(e):
        raise RuntimeError(f"refusing non-perf email: {email}")
    return e


def pair_key(a: str, b: str) -> str:
    x = sorted([a.strip().lower(), b.strip().lower()])
    return "|".join(x)


def find_existing_dm(
    supabase_url: str, anon_key: str, token: str, me: str, them: str
) -> str | None:
    base = supabase_url.rstrip("/") + "/rest/v1/"
    status, mine = http_json(
        "GET",
        base + f"conversation_participants?user_id=eq.{me}&select=conversation_id",
        rest_headers(anon_key, token),
    )
    if status != 200 or not isinstance(mine, list):
        return None
    ids = list({row["conversation_id"] for row in mine if row.get("conversation_id")})
    if not ids:
        return None
    in_list = ",".join(ids)
    status, rows = http_json(
        "GET",
        base
        + f"conversation_participants?conversation_id=in.({in_list})&select=conversation_id,user_id",
        rest_headers(anon_key, token),
    )
    if status != 200 or not isinstance(rows, list):
        return None
    by_convo: dict[str, set[str]] = {}
    for row in rows:
        cid = row["conversation_id"]
        by_convo.setdefault(cid, set()).add(row["user_id"])
    candidates = [cid for cid, u in by_convo.items() if u == {me, them}]
    if not candidates:
        return None
    in_c = ",".join(candidates)
    status, meta = http_json(
        "GET",
        base + f"conversations?id=in.({in_c})&select=id,is_group",
        rest_headers(anon_key, token),
    )
    if status != 200 or not isinstance(meta, list):
        return candidates[0]
    for conv in meta:
        if not conv.get("is_group"):
            return conv["id"]
    return None


def ensure_dm(
    supabase_url: str,
    anon_key: str,
    actor: dict,
    other_id: str,
    dry_run: bool,
) -> str:
    existing = find_existing_dm(
        supabase_url, anon_key, actor["token"], actor["user_id"], other_id
    )
    if existing:
        return existing

    if dry_run:
        return str(uuid.uuid4())

    base = supabase_url.rstrip("/") + "/rest/v1/"
    block_url = base + "rpc/users_have_active_block"
    status, blocked = http_json(
        "POST",
        block_url,
        rest_headers(anon_key, actor["token"]),
        {"p_user_a": actor["user_id"], "p_user_b": other_id},
    )
    if status == 200 and blocked is True:
        raise RuntimeError(f"block active between {actor['email']} and {other_id}")

    conv_id = str(uuid.uuid4())
    status, err = http_json(
        "POST",
        base + "conversations",
        rest_headers(anon_key, actor["token"], "return=minimal"),
        {"id": conv_id, "is_group": False},
    )
    if status not in (200, 201, 204):
        raise RuntimeError(f"conversations insert: HTTP {status} {err}")

    status, err = http_json(
        "POST",
        base + "conversation_participants",
        rest_headers(anon_key, actor["token"], "return=minimal"),
        [
            {"conversation_id": conv_id, "user_id": actor["user_id"]},
            {"conversation_id": conv_id, "user_id": other_id},
        ],
    )
    if status not in (200, 201, 204):
        raise RuntimeError(f"conversation_participants insert: HTTP {status} {err}")
    return conv_id


def find_room_by_name(
    supabase_url: str, anon_key: str, token: str, room_name: str
) -> dict | None:
    q = urllib.parse.quote(f'eq.{room_name}')
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/rooms?name={q}&select=id,name,owner_user_id,is_private,join_policy,show_on_profile"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, token))
    if status != 200 or not isinstance(rows, list) or not rows:
        return None
    return rows[0]


def list_owned_room(
    supabase_url: str, anon_key: str, session: dict
) -> dict | None:
    uid = session["user_id"]
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/rooms?owner_user_id=eq.{uid}&select=id,name,owner_user_id,is_private,join_policy,show_on_profile"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, session["token"]))
    if status != 200 or not isinstance(rows, list) or not rows:
        return None
    return rows[0]


def session_for_user_id(email_to_user: dict[str, dict], user_id: str) -> dict:
    for s in email_to_user.values():
        if s["user_id"] == user_id:
            return s
    raise RuntimeError(f"no session for user_id {user_id}")


def room_allows_perf_self_join(room: dict) -> bool:
    if room.get("is_private"):
        return False
    return (room.get("join_policy") or "open").lower() == "open"


def assert_loadtest_room_metadata(room: dict, expected_name: str) -> None:
    if room.get("name") != expected_name:
        raise RuntimeError(
            f"refusing room {room.get('id')}: name {room.get('name')!r} "
            f"!= spec {expected_name!r}"
        )
    if not room_allows_perf_self_join(room):
        raise RuntimeError(
            f"refusing room {room.get('id')}: must be is_private=false and join_policy=open"
        )


def active_room_member_ids(
    supabase_url: str, anon_key: str, token: str, room_id: str
) -> set[str]:
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/room_members?room_id=eq.{room_id}&left_at=is.null&select=user_id"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, token))
    if status != 200 or not isinstance(rows, list):
        raise RuntimeError(f"room_members list: HTTP {status} {rows!r}")
    return {row["user_id"] for row in rows if row.get("user_id")}


def assert_room_perf_exclusive(
    member_ids: set[str], perf_ids: set[str], *, room_id: str
) -> None:
    extra = member_ids - perf_ids
    if extra:
        raise RuntimeError(
            f"refusing room {room_id}: {len(extra)} non-perf active member(s)"
        )


def assert_room_all_perf_joined(
    member_ids: set[str], perf_ids: set[str], *, room_id: str
) -> None:
    assert_room_perf_exclusive(member_ids, perf_ids, room_id=room_id)
    missing = perf_ids - member_ids
    if missing:
        raise RuntimeError(
            f"room {room_id} missing {len(missing)} perf member(s) after join pass"
        )


def find_loadtest_room_by_name(
    supabase_url: str,
    anon_key: str,
    sessions: list[dict],
    expected_name: str,
) -> dict | None:
    for i, session in enumerate(sessions):
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        room = find_room_by_name(supabase_url, anon_key, session["token"], expected_name)
        if room:
            return room
    return None


def find_loadtest_room_owned_by_perf(
    supabase_url: str,
    anon_key: str,
    member_emails: list[str],
    email_to_user: dict[str, dict],
    expected_name: str,
) -> dict | None:
    for i, raw_email in enumerate(member_emails):
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        email = assert_perf_email(raw_email)
        session = email_to_user[email]
        owned = list_owned_room(supabase_url, anon_key, session)
        if owned and owned.get("name") == expected_name:
            return owned
    return None


def creators_without_owned_room(
    supabase_url: str,
    anon_key: str,
    member_emails: list[str],
    email_to_user: dict[str, dict],
) -> list[dict]:
    candidates: list[dict] = []
    for i, raw_email in enumerate(member_emails):
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        email = assert_perf_email(raw_email)
        session = email_to_user[email]
        owned = list_owned_room(supabase_url, anon_key, session)
        if owned:
            print(
                f"  skip create: {email} already owns room {owned['id']} ({owned.get('name')!r})"
            )
            continue
        candidates.append(session)
    return candidates


def fetch_room_row(
    supabase_url: str, anon_key: str, token: str, room_id: str
) -> dict:
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/rooms?id=eq.{room_id}"
        + "&select=id,name,owner_user_id,is_private,join_policy,show_on_profile"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, token))
    if status != 200 or not isinstance(rows, list) or not rows:
        raise RuntimeError(f"rooms read {room_id}: HTTP {status}")
    return rows[0]


def ensure_room_joinable_for_self_insert(
    supabase_url: str,
    anon_key: str,
    owner_session: dict,
    room_id: str,
    *,
    dry_run: bool,
) -> None:
    """
    Phase 1 RLS: open self-join needs rooms_select_profile_public (show_on_profile).
    Owner PATCH only — same field iOS/web room settings use; no policy changes.
    """
    if dry_run:
        print(
            "  [dry-run] owner ensures show_on_profile=true so perf accounts can "
            "self-join (room_members_insert_self rooms EXISTS check)"
        )
        return

    room = fetch_room_row(supabase_url, anon_key, owner_session["token"], room_id)
    if not room_allows_perf_self_join(room):
        raise RuntimeError(
            f"room {room_id} must stay is_private=false and join_policy=open for perf self-join"
        )
    if room.get("show_on_profile") is True:
        return

    patch = supabase_url.rstrip("/") + f"/rest/v1/rooms?id=eq.{room_id}"
    status, err = http_json(
        "PATCH",
        patch,
        rest_headers(anon_key, owner_session["token"], "return=minimal"),
        {"show_on_profile": True},
    )
    if status not in (200, 204):
        raise RuntimeError(f"rooms show_on_profile PATCH: HTTP {status} {err}")
    print(f"  set show_on_profile=true on {room_id} (required for open self-join RLS)")


def rpc_trade_room_invite_lookup(
    supabase_url: str, anon_key: str, session: dict, room_id: str
) -> None:
    """Parity with iOS deep-link resolution before join; security definer read."""
    url = supabase_url.rstrip("/") + "/rest/v1/rpc/rpc_v1_trade_room_invite_lookup"
    status, body = http_json(
        "POST",
        url,
        rest_headers(anon_key, session["token"]),
        {"p_ref": room_id},
    )
    if status != 200:
        raise RuntimeError(f"rpc_v1_trade_room_invite_lookup: HTTP {status} {body}")
    if body is None or body == "null":
        raise RuntimeError(f"invite lookup returned null for room {room_id}")


def is_active_member(
    supabase_url: str, anon_key: str, token: str, room_id: str, user_id: str
) -> bool:
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/room_members?room_id=eq.{room_id}&user_id=eq.{user_id}&select=left_at"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, token))
    if status != 200 or not isinstance(rows, list) or not rows:
        return False
    return rows[0].get("left_at") is None


def join_room_self(
    supabase_url: str, anon_key: str, session: dict, room_id: str, dry_run: bool
) -> None:
    """Same PostgREST paths as joinTradeRoom / DefaultRoomRepository.join (no notify)."""
    if is_active_member(supabase_url, anon_key, session["token"], room_id, session["user_id"]):
        return
    if dry_run:
        return

    rpc_trade_room_invite_lookup(supabase_url, anon_key, session, room_id)

    url = supabase_url.rstrip("/") + "/rest/v1/room_members"
    status, err = http_json(
        "POST",
        url,
        rest_headers(anon_key, session["token"], "return=minimal"),
        {
            "room_id": room_id,
            "user_id": session["user_id"],
            "notification_enabled": False,
        },
    )
    if status in (200, 201, 204):
        return
    if status == 409 or (isinstance(err, dict) and err.get("code") == "23505"):
        patch = (
            supabase_url.rstrip("/")
            + f"/rest/v1/room_members?room_id=eq.{room_id}&user_id=eq.{session['user_id']}"
        )
        status2, err2 = http_json(
            "PATCH",
            patch,
            rest_headers(anon_key, session["token"], "return=minimal"),
            {"left_at": None, "notification_enabled": False},
        )
        if status2 in (200, 204):
            return
        raise RuntimeError(f"room_members reactivate: HTTP {status2} {err2}")
    if status == 403 or (isinstance(err, dict) and err.get("code") == "42501"):
        raise RuntimeError(
            f"room_members insert: HTTP {status} {err} — open self-join requires "
            "show_on_profile=true (rooms_select_profile_public) for non-members; "
            "ensure_room_joinable_for_self_insert should run as owner first"
        )
    raise RuntimeError(f"room_members insert: HTTP {status} {err}")


def rpc_create_loadtest_room(
    supabase_url: str, anon_key: str, creator: dict, room_spec: dict
) -> str:
    name = room_spec["displayName"]
    url = supabase_url.rstrip("/") + "/rest/v1/rpc/rpc_v1_create_trade_room"
    payload = {
        "p_name": name,
        "p_description": "Perf-only load test isolation (realistic300_full). Not for real users.",
        "p_image_url": None,
        "p_show_on_profile": True,
        "p_is_private": False,
        "p_category": "general",
        "p_discovery_tags": [],
        "p_join_policy": "open",
        "p_rules": "Load test room — perf accounts only.",
        "p_members_can_message": True,
        "p_members_can_share_trades": False,
        "p_members_can_share_media": False,
        "p_channels": [{"name": "general", "allow_members_chat": True}],
    }
    status, body = http_json(
        "POST", url, rest_headers(anon_key, creator["token"]), payload
    )
    if status != 200:
        msg = body.get("message") if isinstance(body, dict) else body
        code = body.get("code") if isinstance(body, dict) else None
        if (isinstance(msg, str) and "owned_room_exists" in msg) or code == "23505":
            raise OwnedRoomExistsError(creator["email"])
        raise RuntimeError(f"rpc_v1_create_trade_room: HTTP {status} {body}")
    if isinstance(body, dict) and body.get("id"):
        return body["id"]
    if isinstance(body, str):
        try:
            parsed = json.loads(body)
            if parsed.get("id"):
                return parsed["id"]
        except json.JSONDecodeError:
            pass
    raise RuntimeError(f"create room returned unexpected body: {body!r}")


class OwnedRoomExistsError(RuntimeError):
    def __init__(self, email: str) -> None:
        super().__init__(f"owned_room_exists for {email}")
        self.email = email


def resolve_loadtest_room(
    supabase_url: str,
    anon_key: str,
    room_spec: dict,
    email_to_user: dict[str, dict],
    *,
    dry_run: bool,
) -> tuple[str, dict]:
    """Return (room_id, owner_session). Reuse or create without touching other rooms."""
    expected_name = room_spec["displayName"]
    member_emails: list[str] = room_spec["memberEmails"]
    perf_ids = {s["user_id"] for s in email_to_user.values()}
    sessions = [email_to_user[assert_perf_email(e)] for e in member_emails]

    if not dry_run:
        existing = find_loadtest_room_by_name(
            supabase_url, anon_key, sessions, expected_name
        )
        if not existing:
            existing = find_loadtest_room_owned_by_perf(
                supabase_url, anon_key, member_emails, email_to_user, expected_name
            )
        if existing:
            assert_loadtest_room_metadata(existing, expected_name)
            members = active_room_member_ids(
                supabase_url,
                anon_key,
                session_for_user_id(email_to_user, existing["owner_user_id"])["token"],
                existing["id"],
            )
            assert_room_perf_exclusive(members, perf_ids, room_id=existing["id"])
            owner = session_for_user_id(email_to_user, existing["owner_user_id"])
            print(
                f"  reuse room {existing['id']} ({expected_name!r}), "
                f"{len(members)} active perf member(s)"
            )
            return existing["id"], owner

    if dry_run:
        print(
            f"  [dry-run] find room by name {expected_name!r} or create via first "
            "perf account without an owned room (see rooms_owner_user_id_unique_idx)"
        )
        return str(uuid.uuid4()), sessions[0]

    candidates = creators_without_owned_room(
        supabase_url, anon_key, member_emails, email_to_user
    )
    if not candidates:
        raise RuntimeError(
            "no perf account can create the loadtest room: all listed accounts "
            "already own a room (owned_room_exists). Reuse requires an existing "
            f"room named {expected_name!r} with perf-only members."
        )

    last_err: Exception | None = None
    for creator in candidates:
        print(f"  create room as {creator['email']}")
        try:
            room_id = rpc_create_loadtest_room(
                supabase_url, anon_key, creator, room_spec
            )
            print(f"  created room → {room_id}")
            return room_id, creator
        except OwnedRoomExistsError as e:
            print(f"  owned_room_exists for {e.email}, trying next candidate")
            last_err = e
            continue
    raise RuntimeError(
        "rpc_v1_create_trade_room failed for every eligible perf account"
    ) from last_err


def verify_direct_conversations(
    supabase_url: str,
    anon_key: str,
    email_to_user: dict[str, dict],
    dm_map: dict[str, str],
    spec: dict,
) -> None:
    perf_ids = {s["user_id"] for s in email_to_user.values()}
    base = supabase_url.rstrip("/") + "/rest/v1/"
    expected_pairs = len(spec["directConversationPairs"])
    if len(dm_map) != expected_pairs:
        raise RuntimeError(f"expected {expected_pairs} DMs, got {len(dm_map)}")
    for pair in spec["directConversationPairs"]:
        a = assert_perf_email(pair[0])
        b = assert_perf_email(pair[1])
        key = pair_key(a, b)
        cid = dm_map.get(key)
        if not cid:
            raise RuntimeError(f"missing DM id for {key}")
        token = email_to_user[a]["token"]
        status, meta = http_json(
            "GET",
            base + f"conversations?id=eq.{cid}&select=id,is_group",
            rest_headers(anon_key, token),
        )
        if status != 200 or not isinstance(meta, list) or not meta:
            raise RuntimeError(f"DM {cid} not readable")
        if meta[0].get("is_group"):
            raise RuntimeError(f"DM {cid} is a group conversation")
        status, parts = http_json(
            "GET",
            base
            + f"conversation_participants?conversation_id=eq.{cid}&select=user_id",
            rest_headers(anon_key, token),
        )
        if status != 200 or not isinstance(parts, list):
            raise RuntimeError(f"DM {cid} participants unreadable")
        part_ids = {p["user_id"] for p in parts}
        want = {email_to_user[a]["user_id"], email_to_user[b]["user_id"]}
        if part_ids != want:
            raise RuntimeError(f"DM {cid} participants mismatch")
        if not part_ids <= perf_ids:
            raise RuntimeError(f"DM {cid} has non-perf participant")


def get_first_section_id(
    supabase_url: str, anon_key: str, token: str, room_id: str
) -> str | None:
    url = (
        supabase_url.rstrip("/")
        + f"/rest/v1/room_sections?room_id=eq.{room_id}&select=id&order=position.asc&limit=1"
    )
    status, rows = http_json("GET", url, rest_headers(anon_key, token))
    if status == 200 and isinstance(rows, list) and rows:
        return rows[0].get("id")
    return None


def build_fixture(spec: dict, dm_map: dict[str, str], room_id: str, section_id: str | None) -> dict:
    direct = []
    for pair in spec["directConversationPairs"]:
        key = pair_key(pair[0], pair[1])
        direct.append(
            {
                "id": dm_map[key],
                "participantEmails": [pair[0], pair[1]],
            }
        )
    trade_rooms = []
    for room in spec["tradeRooms"]:
        trade_rooms.append(
            {
                "id": room_id,
                "sectionId": section_id,
                "memberEmails": room["memberEmails"],
            }
        )
    return {
        "schemaVersion": 1,
        "tag": spec["tag"],
        "directConversations": direct,
        "tradeRooms": trade_rooms,
        "inboxRealtimeConversationIds": [],
    }


def validate_spec_vs_users(spec: dict, users: list[dict]) -> None:
    emails = {assert_perf_email(u["email"]) for u in users}
    if len(emails) != EXPECTED_USER_COUNT:
        raise RuntimeError(f"expected {EXPECTED_USER_COUNT} perf users, got {len(emails)}")
    participants: set[str] = set()
    for pair in spec["directConversationPairs"]:
        participants.add(assert_perf_email(pair[0]))
        participants.add(assert_perf_email(pair[1]))
    for room in spec["tradeRooms"]:
        for e in room["memberEmails"]:
            participants.add(assert_perf_email(e))
    if participants != emails:
        missing = sorted(emails - participants)
        extra = sorted(participants - emails)
        raise RuntimeError(
            f"fixture spec must list exactly {USERS_ENV_KEY} emails; "
            f"missing={missing[:5]} extra={extra[:5]}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Provision realistic600_full isolation fixture")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate and print planned writes without calling production",
    )
    args = parser.parse_args()

    file_env = load_env_file()
    import os

    for k, v in file_env.items():
        os.environ.setdefault(k, v)

    if os.environ.get("LOADTEST_ENV") != "production":
        sys.exit("error: LOADTEST_ENV must be production")
    if not args.dry_run and os.environ.get("TRADETRAXS_PROD_PERF_FIXTURE_PROVISION") != "yes":
        sys.exit(
            "error: set TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes to allow production writes"
        )

    supabase_url = os.environ.get("LOADTEST_SUPABASE_URL", "")
    anon_key = os.environ.get("LOADTEST_SUPABASE_ANON_KEY", "")
    if PRODUCTION_PROJECT_REF not in supabase_url:
        sys.exit("error: LOADTEST_SUPABASE_URL must be production project ref")
    if "service_role" in anon_key or "c2VydmljZV9yb2xl" in anon_key:
        sys.exit("error: refuse service_role key")

    if USERS_ENV_KEY not in os.environ or not os.environ[USERS_ENV_KEY].strip():
        sys.exit(f"error: missing {USERS_ENV_KEY} (100 perf accounts; run provision-prod-perf-accounts.py --realistic600 first)")
    users = json.loads(os.environ[USERS_ENV_KEY])
    spec = json.loads(SPEC_FILE.read_text())
    validate_spec_vs_users(spec, users)

    email_to_user: dict[str, dict] = {}
    for i, u in enumerate(users):
        email = assert_perf_email(u["email"])
        if args.dry_run:
            email_to_user[email] = {
                "email": u["email"],
                "user_id": str(uuid.uuid4()),
                "token": "dry-run",
            }
            continue
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        email_to_user[email] = password_grant(
            supabase_url, anon_key, u["email"], u["password"]
        )

    dm_map: dict[str, str] = {}
    print(f"DM pairs: {len(spec['directConversationPairs'])}")
    for i, pair in enumerate(spec["directConversationPairs"]):
        a = assert_perf_email(pair[0])
        b = assert_perf_email(pair[1])
        key = pair_key(a, b)
        actor = email_to_user[a]
        other_id = email_to_user[b]["user_id"]
        if args.dry_run:
            print(f"  [dry-run] ensure DM {pair[0]} ↔ {pair[1]}")
            dm_map[key] = str(uuid.uuid4())
            continue
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        cid = ensure_dm(supabase_url, anon_key, actor, other_id, dry_run=False)
        dm_map[key] = cid
        print(f"  DM {key} → {cid}")

    room_spec = spec["tradeRooms"][0]
    print(f"Trade room: {room_spec['displayName']}")
    if not args.dry_run:
        time.sleep(AUTH_SPACING_SEC)
    room_id, owner_session = resolve_loadtest_room(
        supabase_url,
        anon_key,
        room_spec,
        email_to_user,
        dry_run=args.dry_run,
    )
    if not args.dry_run:
        print(f"  room id → {room_id}")

    ensure_room_joinable_for_self_insert(
        supabase_url,
        anon_key,
        owner_session,
        room_id,
        dry_run=args.dry_run,
    )

    perf_ids = {s["user_id"] for s in email_to_user.values()}
    for i, u in enumerate(users):
        session = email_to_user[assert_perf_email(u["email"])]
        if args.dry_run:
            print(f"  [dry-run] join room as {u['email']}")
            continue
        if i > 0:
            time.sleep(AUTH_SPACING_SEC)
        join_room_self(supabase_url, anon_key, session, room_id, dry_run=False)

    section_id = None
    if args.dry_run:
        print(f"\n[dry-run] would verify 50 DMs + {EXPECTED_USER_COUNT} room members, then write", OUT_FIXTURE)
        print("[dry-run] ok — no production mutations")
        return

    verify_direct_conversations(
        supabase_url, anon_key, email_to_user, dm_map, spec
    )
    print("  verified 50 DM conversations (perf-only, 1:1)")

    members = active_room_member_ids(
        supabase_url, anon_key, owner_session["token"], room_id
    )
    assert_room_all_perf_joined(members, perf_ids, room_id=room_id)
    print(f"  verified room membership: {len(members)} perf accounts")

    room_row = fetch_room_row(supabase_url, anon_key, owner_session["token"], room_id)
    if not room_allows_perf_self_join(room_row):
        raise RuntimeError(f"room {room_id} is not open public join")
    if room_row.get("show_on_profile") is not True:
        raise RuntimeError(
            f"room {room_id} show_on_profile must be true for verified self-join RLS"
        )

    section_id = get_first_section_id(
        supabase_url, anon_key, owner_session["token"], room_id
    )

    fixture = build_fixture(spec, dm_map, room_id, section_id)
    OUT_FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n")
    one_line = json.dumps(fixture, separators=(",", ":"))
    print(f"\nWrote {OUT_FIXTURE}")
    print("\nAdd to loadtest/.env.production-perf:")
    print(f"LOADTEST_REALISTIC600_FULL_FIXTURE_FILE={OUT_FIXTURE.relative_to(ROOT)}")
    print("# or:")
    print(f"LOADTEST_REALISTIC600_FULL_FIXTURE_JSON='{one_line}'")


if __name__ == "__main__":
    main()
