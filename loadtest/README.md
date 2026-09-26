# Phase A read load test

Small k6 script for staging. It does not run by itself.

Each virtual user logs in once, then walks one short read path with a few seconds of idle time between screens. Paths rotate across users: dashboard, feed and one extra page, profile, trades, leaderboard, and the messages inbox.

## Safety

The script exits immediately unless `LOADTEST_ENV=staging`.

It also refuses:

- `tradetraxs.com`, `www.tradetraxs.com`, and `app.tradetraxs.com`
- the production Supabase project ref `fobudrkniacatvilbofw`
- a key that is a service-role credential

Use dedicated staging users such as `loadtest-user-001`. Do not put production passwords in `loadtest/.env`.

## Setup

```bash
cp loadtest/.env.example loadtest/.env
```

Fill `loadtest/.env` with the staging Supabase URL, staging anon key, staging web origin, and staging test users. `LOADTEST_MAX_VUS` stays `10` for the first run.

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
