# Provision realistic600_full isolation fixture (operator)

**Separate from realistic300_full** (50 accounts / 25 DMs). Uses **100 perf accounts**, **50 DMs**, dedicated trade room.

## Order of operations

1. **Accounts** — extend existing 50-user pool (reuse anchor + perfload02–50):

   ```bash
   python3 loadtest/scripts/provision-prod-perf-accounts.py --realistic600
   ```

   Creates **perfload51–100** only; writes `LOADTEST_REALISTIC600_USERS_JSON` (does not replace `LOADTEST_USERS_JSON`).

   **Resumable:** merges any partial `LOADTEST_REALISTIC600_USERS_JSON` over slots 50–99, skips accounts that already have credentials, and **writes the env file after each successful signup**. Auth **429** is retried using **Retry-After** or exponential backoff with jitter (up to 60s). Default **3s** spacing between signups (`--signup-spacing` or `TRADETRAXS_PERF_AUTH_SIGNUP_SPACING_SEC`). Re-run the same command to continue at the first missing slot (e.g. perfload84). Existing follow graphs are not resynced for accounts that were already filled at start.

   If a prior run created Auth users but never persisted passwords, use **`loadtest/scripts/recover-realistic600-perf-passwords.py`** (Admin Auth, perfload51–83 only) before resuming signup for perfload84–100.

2. **Fixture** — DMs + room + UUID JSON:

   ```bash
   python3 loadtest/scripts/provision-realistic600-full-fixture.py --dry-run
   export TRADETRAXS_PROD_PERF_FIXTURE_PROVISION=yes
   python3 loadtest/scripts/provision-realistic600-full-fixture.py
   ```

3. **Env** — add to `loadtest/.env.production-perf`:

   ```bash
   LOADTEST_FULL_MESSAGE_TAG=[loadtest:realistic600_full]
   LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
   ```

4. **Verify** — `./loadtest/scripts/verify-realistic600-full-env.sh --config-only`

Email topology: `loadtest/fixtures/realistic600-full-isolation.email-spec.json`

## Safety

Same as 300_full: perf email regex, no notify APIs, idempotent DM/room, `show_on_profile=true` for open self-join RLS.

First **25** DM pairs match the 300_full graph (existing conversations reused). Pairs **26–50** cover perfload51–100.

## Cleanup

```bash
export LOADTEST_REALISTIC600_FULL_FIXTURE_FILE=loadtest/fixtures/realistic600-full-isolation.json
node loadtest/scripts/cleanup-realistic300-full-data.mjs --dry-run --realistic600
```
