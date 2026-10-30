# Onefifty (150 VU): 50 dedicated test accounts

`onefifty` requires **exactly 50** entries in `LOADTEST_USERS_JSON`. VUs assign accounts via round-robin: `(vu.idInTest - 1) % 50`.

## Account layout

| Index | Account |
|-------|---------|
| `users[0]` | `tradetraxsdemo@gmail.com` (anchor — never created by script) |
| `users[1..49]` | `tradetraxsdemo+perfload02@gmail.com` … `perfload50@gmail.com` |

Feed workload uses **`LOADTEST_FEED_SCOPE=following`**. Each perf account needs **10–20 follows** of public creators (deterministic per slot via `provision-prod-perf-accounts.py`). No new public posts are created; Following feed reads followees’ existing content.

## Provision perfload31–50 (operator)

**Prerequisites**

- `loadtest/.env.production-perf` already has **30** valid users (anchor + perfload02–30).
- `LOADTEST_SUPABASE_URL` / anon key point at production ref **`fobudrkniacatvilbofw`**.
- `chmod 600 loadtest/.env.production-perf`

**Command** (creates Auth users 31–50, profiles, follow graphs; updates JSON to 50 entries; **does not** re-sync follows for slots 0–29):

```bash
cd /path/to/trade-journal
python3 loadtest/scripts/provision-prod-perf-accounts.py --onefifty
```

If signup requires email confirmation, confirm Gmail aliases then re-run the same command (idempotent for filled slots).

**Legacy 30-account provision** (full signup for empty slots 1–29 only):

```bash
python3 loadtest/scripts/provision-prod-perf-accounts.py
```

## Verify + 150-VU k6 (manual)

Ensure `loadtest/.env.production-perf` includes:

```bash
LOADTEST_PROD_PERF_MODE=onefifty
LOADTEST_MAX_VUS=150
TRADETRAXS_PROD_PERF_ONEFIFTY=yes
LOADTEST_WORKLOAD_KIND=client_realistic
LOADTEST_FEED_SCOPE=following
LOADTEST_VU_START_JITTER_SEC=12
TRADETRAXS_PROD_PERF_CONFIRM=yes
LOADTEST_ENV=production
```

Then:

```bash
./loadtest/scripts/verify-production-perf-env.sh
```

`verify` checks **50** users, unique emails, and runs password-grant preflight for all 50. **Do not** run `preflight-prod-perf-auth.sh` again immediately before k6.

```bash
set -a && source loadtest/.env.production-perf && set +a
k6 run loadtest/prod-read-perf.js
```

Monitor Supabase during the 60s window per `loadtest/PRODUCTION_READ_PERF.md`.
