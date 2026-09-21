# Calendar V2 — production QA checklist (Phase 3B)

## Enable V2 (Debug / TestFlight only)

- Xcode scheme env: `BACKEND_V2_CALENDAR_ANALYTICS_V2=1`
- Or UserDefaults: `backendV2.calendarAnalyticsV2` = true

`productionShippedFlags` stays **OFF** until QA sign-off.

## Device log flow

1. Launch → Dashboard usable → Calendar
2. September 2026 → prev month → back to September
3. Account filter A → B → All Accounts
4. Tap populated day → back → Dashboard

Filter Xcode console: `[CalendarV2]` and `[CalendarDay]`.

Backend V2 RPC lines also log: `exec=…ms decode=…ms bytes=…`.

## JWT RLS (CI / local)

```bash
export SUPABASE_URL=…
export SUPABASE_ANON_KEY=…
export ANALYTICS_TEST_JWT_USER_A=…   # owner session access token
export ANALYTICS_TEST_JWT_USER_B=…   # second user
export ANALYTICS_TEST_USER_B_ID=…    # B's auth.users UUID
node scripts/analytics-jwt-rls-integration.mjs
```

Script loads `.env.local` for `NEXT_PUBLIC_SUPABASE_*` when set.

## Server-side parity (no JWT)

September 2026 global check: `trade_daily_stats` vs `analytics_calendar_day` trade counts — **0 mismatches** on production after Phase 3B deploy.
