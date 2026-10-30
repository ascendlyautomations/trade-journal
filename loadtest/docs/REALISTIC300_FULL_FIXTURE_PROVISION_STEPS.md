# Provision realistic300_full isolation fixture (operator)

Automated script (recommended): **`loadtest/scripts/provision-realistic300-full-fixture.py`**

Manual steps below are optional if you prefer the app UI; the script uses the same PostgREST/RPC paths as production clients.

## Safety gates

| Gate | Purpose |
|------|---------|
| `LOADTEST_ENV=production` | Staging blocked |
| `TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes` | Required for **live** provision (not `--dry-run`) |
| Perf email regex | Only `tradetraxsdemo@gmail.com` and `tradetraxsdemo+perfload02`…`50` |
| No message inserts | No `notify-dm` / notification HTTP |
| Idempotent | Reuses existing 1:1 DMs and named trade room |

## Trade room ownership (one room per user)

Production enforces **at most one owned room per user** (`rooms_owner_user_id_unique_idx`; `rpc_v1_create_trade_room` → `owned_room_exists` / SQL `23505`).

The provision script:

1. **Reuses** a room only when its **name matches** the email spec (`TT Loadtest Full v1 (private, perf-only)`) and every **active member** is a perf account (no real users).
2. Otherwise **creates** the room as the **first** spec-listed perf account that does **not** already own a room (typically not `tradetraxsdemo@gmail.com` if that account already owns a personal room).
3. Never deletes or reassigns existing rooms.

## Trade room visibility (RLS)

True **private** rooms cannot accept bulk perf joins via JWT-only flows (`room_not_requestable` on join requests; `room_members` self-insert requires **open** + **non-private**).

**Why `show_on_profile=true`:** `room_members_insert_self` includes `EXISTS (SELECT 1 FROM rooms …)`. That subquery runs as the **joiner** under RLS. Non-members cannot `SELECT` a room with `show_on_profile=false`, so self-insert returns **403 / 42501** even when `join_policy=open`. This matches production iOS/web (`DefaultRoomRepository.join` / `joinTradeRoom`) — not a service-role bypass.

The loadtest room is **perf-isolated by membership + fixture**, not by hiding the row from RLS:

- Distinctive name from the email spec  
- `join_policy=open`, `is_private=false`  
- `show_on_profile=true` (set on create; owner PATCH idempotent on reruns for room `75a3b357-…` and similar)  
- Each perf account **self-joins** via PostgREST (no `/api/notifications/room-join` or join-request notify)

DM shells are normal **1:1** `conversations` + `conversation_participants` (no messages).

## Commands

**Dry-run** (validate spec ↔ 50 users, print plan — no Auth, no writes):

```bash
cd /path/to/trade-journal
set -a && source loadtest/.env.production-perf && set +a
python3 loadtest/scripts/provision-realistic300-full-fixture.py --dry-run
```

**Execute** (production writes — review dry-run first):

```bash
set -a && source loadtest/.env.production-perf && set +a
export TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes
python3 loadtest/scripts/provision-realistic300-full-fixture.py
```

Output: `loadtest/fixtures/realistic300-full-isolation.json` + suggested `.env` lines.

**Verify config** (no 50× Auth):

```bash
./loadtest/scripts/verify-realistic300-full-env.sh --config-only
```

Ensure `.env.production-perf` includes:

```bash
TRADETRAXS_PROD_PERF_REALISTIC300_FULL=yes
LOADTEST_MAX_VUS=300
LOADTEST_REALISTIC300_FULL_FIXTURE_FILE=loadtest/fixtures/realistic300-full-isolation.json
```

## Topology (from email spec)

- **25** private 1:1 DMs (adjacent perf pairs + anchor↔perfload02)  
- **1** trade room with **all 50** perf emails as members  

Email list: `loadtest/fixtures/realistic300-full-isolation.email-spec.json`

## After load test

```bash
node loadtest/scripts/cleanup-realistic300-full-data.mjs --dry-run
node loadtest/scripts/cleanup-realistic300-full-data.mjs
```
