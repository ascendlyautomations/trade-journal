# Load tests

Shared k6 contracts and HTTP helpers live under [`loadtest/lib/`](lib/). Preflight and VU scenarios import the same workload modules so RPC signatures, column grants, and response parsing stay aligned with the app (`lib/privacy/loadtestInfrastructure.contract.test.ts`).

## Staging: Phase A read (`phase-a-read.js`)

Small k6 script for staging. It does not run by itself.

## Production read perf (separate — not staging)

Controlled **read-only** production probe: see [`PRODUCTION_READ_PERF.md`](PRODUCTION_READ_PERF.md) and `prod-read-perf.js`. **Not executed by default.**

Each virtual user logs in once, then walks one short read path with a few seconds of idle time between screens. Paths rotate across users: dashboard, feed and one extra page, profile, trades, leaderboard, and the messages inbox.

## Safety

The script exits immediately unless `LOADTEST_ENV=staging`.

It also refuses:

- `tradetraxs.com`, `www.tradetraxs.com`, and `app.tradetraxs.com`
- the production Supabase project ref `fobudrkniacatvilbofw`
- any staging ref other than **`hxlcvffvyadlxcsqxxoy`**
- a key that is a service-role credential
- a Supabase URL that does not match `TRADETRAXS_STAGING_PROJECT_REF` (required)

Use dedicated staging users such as `loadtest-user-001`. Do not put production passwords in `loadtest/.env`.

## Setup

```bash
cp loadtest/.env.example loadtest/.env
```

Fill `loadtest/.env` with `TRADETRAXS_STAGING_PROJECT_REF`, staging Supabase URL, staging anon key, staging web origin, and staging test users. `LOADTEST_MAX_VUS` stays `10` for the first run.

Database bootstrap: see [`supabase/staging/README.md`](../supabase/staging/README.md).

## First run: 1 user, then 10

```bash
set -a && source loadtest/.env && set +a && k6 run loadtest/phase-a-read.js
```

This holds 1 user for 2 minutes, ramps to 10, and holds 10 for 4 minutes. It does not start the test until you run that command.

Later, change `LOADTEST_MAX_VUS` to `25`, `50`, or `100` and run the same command only after the previous stage looked healthy. Allowed values are `1`, `10`, `25`, `50`, and `100`.

## What it calls

| Tag | Call |
| --- | --- |
| `auth` | `POST /auth/v1/token?grant_type=password` |
| `session_profile` | `profiles` row for the signed-in user |
| `dashboard_accounts` | `accounts` for that user |
| `dashboard_window` | newest 120 journal trades |
| `dashboard_history` | full narrow analytics trade history |
| `feed` | `rpc_v1_feed_bootstrap` (global, 8 items) |
| `feed_page` | same RPC with `p_cursor` |
| `profile` | public profile, follower counts, one public trade page |
| `trades` | full journal trade select |
| `leaderboard` | `GET /api/leaderboard/trades` (`leaderboard_ranked_window` on the server) |
| `messages` | `rpc_v2_messaging_bootstrap` with mark-read set to false |

The summary prints requests/sec, failure rate, and p50/p95/p99. Tagged `http_req_duration` lines show which page is slow.

This does not open Realtime sockets and does not seed data.
