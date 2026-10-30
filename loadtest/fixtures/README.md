# realistic300_full isolation fixture

Production conversation and room UUIDs are **operator-owned** (not in git). Email topology is fixed in `realistic300-full-isolation.email-spec.json`.

## What you need

| Asset | Purpose |
|-------|---------|
| **25 private 1:1 DMs** | Adjacent perf pairs + anchor↔perfload02 (see email spec) |
| **1 private trade room** | All **50** perf emails as members (`TT Loadtest Full v1`) |
| **`realistic300-full-isolation.json`** | Gitignored local file with real UUIDs |
| **`LOADTEST_REALISTIC300_FULL_FIXTURE_JSON`** | Same JSON, inlined or via `$(cat …)` when sourcing env |

k6 `setup()` requires every `LOADTEST_USERS_JSON` email to appear in the fixture (room membership satisfies this).

## 1. Provision (recommended)

```bash
set -a && source loadtest/.env.production-perf && set +a
python3 loadtest/scripts/provision-realistic300-full-fixture.py --dry-run
export TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes
python3 loadtest/scripts/provision-realistic300-full-fixture.py
```

See **`loadtest/docs/REALISTIC300_FULL_FIXTURE_PROVISION_STEPS.md`**.

## 2. Discover only (if you provisioned manually in the app)

```bash
node loadtest/scripts/discover-realistic300-full-fixture.mjs
```

## 3. Wire `.env.production-perf`

```bash
LOADTEST_REALISTIC300_FULL_FIXTURE_JSON="$(cat loadtest/fixtures/realistic300-full-isolation.json)"
```

Or paste the single-line output from discover script (`--print-env`).

## 4. Verify (no Auth 429)

```bash
./loadtest/scripts/verify-realistic300-full-env.sh --config-only
```
