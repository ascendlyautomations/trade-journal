# realistic600_full fixture (100 accounts)

Separate from **`realistic300-full-isolation.*`** (50 accounts / 25 DMs).

| File | Purpose |
|------|---------|
| `realistic600-full-isolation.email-spec.json` | 50 DM pairs + 1 room (100 emails) — in git |
| `realistic600-full-isolation.json` | UUID fixture — **gitignored**, from provision script |

Env keys: `LOADTEST_REALISTIC600_USERS_JSON`, `LOADTEST_REALISTIC600_FULL_FIXTURE_*`, `LOADTEST_FULL_MESSAGE_TAG=[loadtest:realistic600_full]`.

See **`loadtest/docs/REALISTIC600_FULL_FIXTURE_PROVISION_STEPS.md`**.

**realistic1000_full** reuses this fixture and `LOADTEST_REALISTIC600_USERS_JSON`; use message tag `[loadtest:realistic1000_full]` and **`loadtest/docs/PROD_PERF_REALISTIC1000_FULL.md`**..
