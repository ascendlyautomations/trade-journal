# Production perf — dedicated accounts (25 / 50 VU / client_realistic)

Use **only** for controlled read load tests. Do not commit credentials. `chmod 600 loadtest/.env.production-perf`.

## Isolation

- Project ref must stay **`fobudrkniacatvilbofw`** with `TRADETRAXS_PROD_PERF_CONFIRM=yes`.
- Staging ref **`hxlcvffvyadlxcsqxxoy`** is blocked by `loadtest/phase-a-read.js`; prod perf uses `loadtest/prod-read-perf.js` only.
- **No** service_role keys, **no** SQL bypass, **no** public test posts.

## 1. Reuse + create accounts (normal Auth / onboarding)

**Reuse:** keep your existing dedicated perf account in `LOADTEST_USERS_JSON` (currently one Gmail-based user tied to profile `tradetraxs_demo`).

**Add four more** via the same path real users use:

1. Sign up at [app.tradetraxs.com](https://app.tradetraxs.com) (email + password you control).
2. Complete onboarding so `public.profiles` exists (trigger / app flow — RLS applies).
3. Use **distinct emails** (e.g. `tradetraxs.perf02@…`, or `yourname+perf02@…`).
4. Store credentials only in `loadtest/.env.production-perf` → `LOADTEST_USERS_JSON`.

Do **not** create users via Dashboard SQL or service_role inserts.

## 2. Following graph (Following Feed scope)

`LOADTEST_FEED_SCOPE=following` requires each account to **follow enough people** that `rpc_v1_feed_bootstrap('following', …)` returns a non-empty first page.

**Target per account:** at least **10–20 follows** of active public creators (more is fine; match real power users ~40 if you want heavier cand work).

**How (RLS-safe):** log in as each test user in the app → Follow on profiles that already publish public trades/posts. No new public content.

**Automated (recommended):**

- `python3 loadtest/scripts/provision-prod-perf-accounts.py` — anchor + perfload02–30 (30 JSON slots).
- `python3 loadtest/scripts/provision-prod-perf-accounts.py --onefifty` — extend to **50** slots (perfload31–50 only; preserves existing 0–29).

Signup + PostgREST `followers` sync (10–20 varied public follows per account) with each user JWT. **Skips** `/api/notifications/follow` so followed users do not get in-app follow notifications from this setup (unlike the full in-app Follow button, which always notifies).

**Suggested seeds (read-only list):** run `loadtest/diagnostics/suggest-perf-follow-targets.sql` in SQL Editor, then follow those profile IDs in the app as each test user.

**Existing perf account:** production shows **`tradetraxs_demo` with only 1 follow** — increase follows before twentyfive or Following feed will mostly hit the empty-following fast path.

## 3. Configure `LOADTEST_USERS_JSON`

Array of `{ "email", "password" }`. **≥5 entries** required for `twentyfive` / `fifty` + `client_realistic`; **15 accounts** recommended for **50 VU**; **30 accounts** required for **100 VU** (`hundred` mode); **exactly 50 accounts** required for **150 VU** (`onefifty` — see `PROD_PERF_ONEFIFTY_FIFTY_USERS.md`).

VU mapping: **`user[(vuId - 1) % N]`** → round-robin across `N` accounts.

Wrap the whole JSON in **single quotes** in `.env.production-perf`:

```bash
LOADTEST_USERS_JSON='[
  {"email":"…account-1…","password":"…"},
  {"email":"…account-2…","password":"…"},
  {"email":"…account-3…","password":"…"},
  {"email":"…account-4…","password":"…"},
  {"email":"…account-5…","password":"…"}
]'
```

## 4. Env checklist (twentyfive / fifty)

| Variable | Twentyfive | Fifty |
|----------|------------|-------|
| `LOADTEST_PROD_PERF_MODE` | `twentyfive` | `fifty` |
| `LOADTEST_MAX_VUS` | `25` | `50` |
| Confirm gate | `TRADETRAXS_PROD_PERF_TWENTYFIVE=yes` | `TRADETRAXS_PROD_PERF_FIFTY=yes` |
| `LOADTEST_WORKLOAD_KIND` | `client_realistic` |
| `LOADTEST_FEED_SCOPE` | `following` |
| `LOADTEST_VU_START_JITTER_SEC` | `12` |

Run **smoke (1 VU)** and **ten** before twentyfive per `loadtest/PRODUCTION_READ_PERF.md`.

**Note:** `verify-production-perf-env.sh` requires **exactly 1** user for `smoke` mode. Either run smoke **before** expanding `LOADTEST_USERS_JSON` to five entries, or temporarily point smoke at a one-element JSON array, then restore five users for twentyfive.

## 5. Verify (no k6 run)

```bash
chmod +x loadtest/scripts/preflight-prod-perf-auth.sh
./loadtest/scripts/verify-production-perf-env.sh
./loadtest/scripts/preflight-prod-perf-auth.sh
```

Preflight prints masked emails only; never logs tokens.

## 6. Optional read-only feed sanity (SQL Editor)

As each user (JWT `sub` = user id), `select public.rpc_v1_feed_bootstrap('following', 'all', 8, null)` should return `page_meta.returned > 0` once follows are seeded.
