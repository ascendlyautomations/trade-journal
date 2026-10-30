# Realistic600_full — overload probe (reads + messaging + Realtime)

**Separate script:** `loadtest/prod-realistic600-full.js` — does **not** change `prod-realistic300-full.js` (300 VU / **50 accounts**).

Same **85% / 15%** workload at **600 VUs** on **100 perf accounts** (**6 VUs per account**, even split) and a **dedicated fixture** (`realistic600-full-isolation.json`).

## Executor

| Phase | Duration | Target VUs |
|-------|----------|------------|
| Ramp up | **5m** | 0 → **600** |
| Sustain | **10m** | **600** |
| Ramp down | **2m** | 600 → 0 |
| Graceful ramp-down | **2m** | (k6) |

## vs realistic300_full

| | 300_full | 600_full |
|--|----------|----------|
| Script | `prod-realistic300-full.js` | `prod-realistic600-full.js` |
| Accounts | `LOADTEST_USERS_JSON` (50) | `LOADTEST_REALISTIC600_USERS_JSON` (100) |
| Fixture | `LOADTEST_REALISTIC300_FULL_FIXTURE_*` | `LOADTEST_REALISTIC600_FULL_FIXTURE_*` |
| Message tag | `[loadtest:realistic300_full]` | `[loadtest:realistic600_full]` |
| VU→user | pseudo-random | **6 sessions per account** |
| Send caps | 200 DM + 200 room | **400 DM + 400 room** (800 total, global partition) |
| Thresholds | abortOnFail SLOs | informational only |

Provision: **`loadtest/docs/REALISTIC600_FULL_FIXTURE_PROVISION_STEPS.md`**

## Environment (600 run)

```bash
TRADETRAXS_PROD_PERF_REALISTIC600_FULL=yes
LOADTEST_MAX_VUS=600
LOADTEST_FULL_MAX_DM_SENDS_TOTAL=400
LOADTEST_FULL_MAX_ROOM_SENDS_TOTAL=400
LOADTEST_FULL_SKIP_PUSH=yes
LOADTEST_FULL_MESSAGE_TAG=[loadtest:realistic600_full]
LOADTEST_REALISTIC600_USERS_JSON='[ ... 100 accounts ... ]'
LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
LOADTEST_VU_START_JITTER_SEC=60
LOADTEST_K6_SETUP_AUTH_SPACING_SEC=3
```

`setup()` performs **one password grant per account** (100 total) with default **3s** spacing between grants, **429 backoff** (Retry-After + exponential jitter, up to 12 retries), then **one** RPC preflight pass using the **first user’s token** (no extra Auth). Do not run `preflight-prod-perf-auth.sh` or verify scripts that password-grant immediately before k6.

Keep **`LOADTEST_USERS_JSON` (50)** unchanged for 300_full runs.

### Supabase Auth rate limits (operator)

Failure `over_request_rate_limit` / HTTP **429** on `/auth/v1/token` means GoTrue’s **request rate limit** for the project (and often **per client IP**) was exceeded. In Dashboard check **Authentication → Rate limits** (signup/token/email limits). Recent account or fixture provisioning from the same IP reduces headroom. Increase `LOADTEST_K6_SETUP_AUTH_SPACING_SEC` (e.g. `4`) if 429 persists after retries; `setupTimeout` is **12m** to allow spacing + backoff.

## Commands

```bash
set -a && source loadtest/.env.production-perf && set +a
./loadtest/scripts/verify-realistic600-full-env.sh --config-only

# Creates loadtest/out/ and exports fixture JSON (k6 cannot mkdir for summary output)
./loadtest/scripts/run-realistic600-full.sh
```

Manual equivalent:

```bash
mkdir -p loadtest/out
set -a && source loadtest/.env.production-perf && set +a
export LOADTEST_REALISTIC600_FULL_FIXTURE_JSON="$(cat loadtest/fixtures/realistic600-full-isolation.json)"
k6 run loadtest/prod-realistic600-full.js
```

Report: `loadtest/out/realistic600-full-last-summary.json` (`messagingAndRealtime`, send caps, HTTP).

## Cleanup

```bash
export LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
node loadtest/scripts/cleanup-realistic300-full-data.mjs --dry-run --realistic600
node loadtest/scripts/cleanup-realistic300-full-data.mjs --realistic600
```

See **`loadtest/docs/PROD_PERF_REALISTIC300_FULL.md`** for workload and metric definitions.
