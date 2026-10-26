# TradeTraxs — Product Analytics, Observability & Technical Debt Audit

**Date:** 2026-10-24  
**Mode:** Read-only repository investigation (no code changes, builds, tests, or simulators).  
**Related:** [INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md) (capacity, cost, resilience).

---

## 1. Executive summary

TradeTraxs has **strong operational data in Postgres** (trades, social graph, billing tables, broker sync state) and a **functional admin analytics RPC**, but **no first-class product analytics pipeline** (no event stream, no retention cohorts, no session instrumentation, no Web/iOS parity on behavioral events).

**What you can measure today (confirmed):**

- **Registered users**, **new signups** (daily series), **aggregate DAU/WAU** (narrow definition), trade/post volumes, support/feedback counts, per-user activity counts (admin), and **Pro/beta filters** on the user directory.
- **Feature usage** only by **ad-hoc SQL** on domain tables (e.g. `trades`, `broker_integration_connections`, `trade_ai_messages`, `vault_items`) — not exposed in product dashboards.

**What is missing or unreliable for growth/retention decisions:**

- **MAU**, **D1/D7/D30 cohort retention**, **sessions**, **session duration**, **last active**, **feed/views**, **messaging/rooms engagement in DAU**, **activation funnel drop-offs**, **walkthrough completion (server-side)**, **Web vs iOS signup split** (unless `signup_flow_source` is populated consistently).
- **Product analytics SDKs** (Amplitude, PostHog, Mixpanel, Segment) — **not present**. Vercel Analytics is **page-level**, cookie-gated, and **not** equivalent to product events.

**Observability:** **Sentry** on web (optional DSN, 10% trace sample in production), structured **Tradovate sync logs**, **APNs** logging with token redaction, and **admin audit** RPCs. **No in-repo alerting**, **no unified cross-platform incident correlation**, **no confirmed iOS crash SDK wiring** in source (architecture doc lists Crashlytics/Sentry as a choice). **Stripe webhook** failures often still return **200 OK** (see infrastructure audit §13).

**Technical debt:** The **Backend V2 dual-path** (15 feature flags; feed/messages default ON, rest mostly OFF) and **very large web Client Components** (~3.3k–5.7k LOC) are the highest maintainability risks. **100+ `rpc_v1_*` / `rpc_v2_*` bootstraps** reduce client fan-out but increase **SQL surface area** to keep consistent. Debt is **manageable** without rewrite if analytics and monitoring gaps are closed incrementally.

---

## 2. Current product analytics capabilities

### 2.1 Instrumentation inventory

| Layer | What exists | Evidence | Product analytics? |
|-------|-------------|----------|-------------------|
| **Third-party product SDK** | None found | Repo grep (no PostHog/Mixpanel/Amplitude/Segment) | **No** |
| **Vercel Analytics + Speed Insights** | Page views / Web Vitals on deployed web, **cookie consent** | `app/components/NativeAwareVercelInsights.tsx`, `@vercel/analytics` in `package.json` | **Partial** (traffic only, not features) |
| **Sentry** | Errors + 10% performance traces (if DSN set) | `lib/sentry.ts`, `instrumentation-client.ts` | **No** (reliability, not retention) |
| **Backend V2 telemetry** | Dev-only `console.debug` | `lib/backendV2/telemetry.ts` (“No analytics service”) | **No** |
| **iOS SessionNetworkProbe** | DEBUG cache/network counters | `SessionNetworkProbe.swift` | **No** |
| **Supabase domain tables** | Implicit “events” via inserts | `trades`, `posts`, `messages`, etc. | **Indirect** (SQL only) |
| **Admin RPCs** | Aggregates + audit feed | `admin_analytics_bundle`, `admin_list_users`, `admin_user_activity_counts`, `admin_recent_audit` | **Yes (internal)** |

### 2.2 Admin dashboard (current)

| Surface | Path | Data source |
|---------|------|-------------|
| Analytics metrics + charts | `app/admin/analytics/page.tsx` | `fetchAdminAnalyticsBundle` → `admin_analytics_bundle` |
| User directory (Pro/beta/ban filters) | `app/admin/users/page.tsx` | `admin_list_users` |
| Per-user activity counts | `lib/adminUsersDirectory.ts` | `admin_user_activity_counts` |
| Activity / audit | `app/admin/activity/page.tsx` | `admin_recent_audit` |
| Beta activity feed | `admin_beta_activity` RPC | Bug reports, feature requests, beta room messages, beta user trades |

**iOS parity:** Admin bundle uses the same RPC via `DefaultAdminUsageAnalyticsRepository.swift` (native admin tooling).

### 2.3 Metric-by-metric measurability

Legend: **Yes** = available in admin/SQL with clear evidence · **Partial** = inferrable with caveats · **No** = not implemented · **Unknown** = needs production validation.

#### User acquisition and growth

| Metric | Status | How / gap | Evidence |
|--------|--------|-----------|----------|
| Total registered users | **Yes** | `totalUsers` = `count(profiles)` | `20260929140000_admin_analytics_bundle_fix_uid_ambiguity.sql` |
| New signups per day/week/month | **Partial** | Daily series `series.usersPerDay`; week = `newUsersWeek` (UTC 7d). **No calendar month rollup in UI** | Same migration + `lib/adminAnalytics.ts` |
| Signup sources / referral | **Partial** | `profiles.referred_by`, `referral_code`; attribution backfill `lib/referralAttribution.ts`, `/api/referral-attribution`. **Not in admin analytics bundle** | `ensureProfileForUser.ts`, session bootstrap fields |
| Web vs iOS registration | **Partial / Unknown** | `profiles.signup_flow_source` exists (`session bootstrap`, `ensureProfileForUser`). **No admin report**; population depends on each client setting the field | `lib/backendV2/contracts.ts`, `lib/ensureProfileForUser.ts` |
| Onboarding completion | **Partial** | `profiles.onboarding_completed`; Getting Started signals RPC | `rpc_v1_getting_started_signals` migrations |
| Onboarding abandonment | **No** | No step-level server events | — |
| Free / trial / paid distribution | **Partial** | Admin user list: `is_pro`, `subscription_status`; DB: `apple_subscriptions`, Stripe fields on `profiles`, `billing_entitlement` API | `admin_list_users`, `lib/billingEntitlement.ts` |
| Account deletion / churn | **Partial** | Delete flows exist (`/api/delete-account`, admin delete). **No churn cohort or deletion reason analytics** | `app/admin/users/page.tsx` |

#### User activity and retention

| Metric | Status | How / gap | Evidence |
|--------|--------|-----------|----------|
| DAU | **Yes (defined)** | Rolling **24h UTC**, distinct users with **creating** activity in listed tables | `DAU_DEFINITION` in `lib/adminAnalytics.ts`; SQL lines 221–234 |
| WAU | **Yes (defined)** | Rolling **7d**, same sources as DAU | SQL lines 236–249 |
| MAU | **No** | Not in `admin_analytics_bundle` | — |
| DAU/MAU ratio | **No** | Requires MAU | — |
| D1 / D7 / D30 retention cohorts | **No** | No cohort RPC or warehouse | — |
| Returning vs new users | **Partial** | Compare signup date to activity dates in SQL (manual) | — |
| Sessions per user | **No** | No session table or SDK | — |
| Average session duration | **No** | — | — |
| Last active date | **Partial** | `max(created_at)` across activity tables per user (custom SQL); **not on `profiles`** | — |
| Dormant / reactivated | **No** | No job or definition in repo | — |

**Critical DAU caveat (confirmed):** DAU counts users who **created** content (trade, feed post, profile post, story, feedback, support ticket). It does **not** include:

- Logging in, viewing feed, reading messages, trade room lurkers, dashboard-only analytics, broker background sync, or AI chat unless it inserts a row in those tables.

Broker auto-sync and worker heartbeats **do not** inflate DAU (good), but **engaged passive users are undercounted** (bad for retention truth).

#### Feature adoption (measurable vs missing)

| Feature | Measurable today? | Source | Admin UI? |
|---------|-------------------|--------|-----------|
| First account created | **Partial** | `accounts.created_at` min by user | No |
| First trade recorded/imported | **Partial** | `trades.created_at`, `import_source`, broker columns | No (only aggregate trade counts) |
| Broker connect attempt/success | **Partial** | `broker_integration_connections`, `broker_integration_account_sync.last_sync_status` | No |
| Trade journal usage | **Partial** | Trade/post counts | Partial (trades) |
| Dashboard / analytics usage | **No** | No view events; optional `user_analytics_state` updates on compute | No |
| Feed views / interactions | **Partial** | Creates: posts, likes, comments (series in RPC **not charted** in admin UI) | Partial (posts only in charts) |
| Posts / clips / achievements | **Partial** | `posts`, `reels`, `achievements` tables | Reels/comments/likes series returned but **not displayed** on `admin/analytics` page |
| Trade Rooms | **Partial** | `room_members`, `room_messages` | Beta room only in `admin_beta_activity` |
| Messaging | **Partial** | `messages`, `conversations` | **Excluded from DAU** |
| AI Analyst | **Partial** | `trade_ai_messages`, `/api/analyze-trade` usage | No |
| Backtest Lab | **Unknown** | Client-side analytics in `lib/backtestLabAnalytics.ts` — **journal-side**, not product telemetry | No |
| Vault saves | **Partial** | `vault_items` (migration `20260906220000_vault_items_folders.sql`) | No |
| Payouts / expenses / income | **Partial** | `account_payout_cycles`, `prop_firm_expenses`, `tracker_income` | No |
| Tax CSV export | **Partial** | Could count export API calls / client actions — **no event table** | `PropFirmExpenseTaxExportModal` |
| Walkthrough complete/skip | **No (server)** | **localStorage / native dismissed map only** | `lib/contextualTour/progressStore.ts`, iOS `ContextualTourCoordinator` |

### 2.4 Web vs iOS event parity

| Area | Web | iOS | Parity |
|------|-----|-----|--------|
| Product behavior events | None centralized | None centralized | N/A |
| Walkthrough state | `localStorage` `tt.contextualTour.dismissed:{userId}` | Same key pattern per comment in `progressStore.ts` | **Device-local only** |
| Getting Started | RPC-driven checklist | Same RPC family | **Yes (server signals)** |
| Admin usage analytics | `admin_analytics_bundle` | Same RPC | **Yes** |
| Performance RPC telemetry | Dev console | iOS Backend V2 flags/tests | **Dev-only** |

### 2.5 Privacy

- **Vercel Analytics** respects `lib/cookieConsent.ts` (`isAnalyticsAllowed()`).
- **Admin** exposes **email** in `admin_list_users` (appropriate for admin-only RPC with `admin_users` gate).
- Product analytics recommendation (§4) should **avoid PII in event payloads** (user id hash ok; no trade PnL, no message body, no broker credentials).
- **Safe logging:** APNs logs redact device tokens (`lib/server/push/apns.ts` comment); iOS `SafeAuthLog.swift` for auth.

---

## 3. Missing retention and engagement metrics

| Priority | Metric | Business impact | Why missing |
|----------|--------|-----------------|-------------|
| P0 | **MAU + DAU/MAU** | Engagement health | No MAU in admin bundle |
| P0 | **D7 / D30 retention cohorts** | Know if product sticks | No cohort job |
| P0 | **Activation funnel** (signup → first trade) | Growth levers | No milestone table |
| P1 | **Session / visit counts** | Frequency of use | No instrumentation |
| P1 | **Last active at (profile or summary table)** | Dormant win-back | Not stored |
| P1 | **Messaging + rooms in activity** | Social retention blind spot | Excluded from DAU |
| P1 | **Broker funnel** (connect → first sync → N trades) | Core value prop | Only connection/sync rows |
| P2 | **Feature adoption dashboard** | Prioritize roadmap | SQL possible, UI absent |
| P2 | **Walkthrough funnel** | Onboarding UX | Local-only dismiss state |
| P2 | **Churn (voluntary delete + subscription lapse)** | Revenue | Deletes not aggregated |

**Confirmed quirk:** `series.followsPerDay` in `admin_analytics_bundle` is **hardcoded to zero** (placeholder CTE), so follow growth is **not** reported despite `followers` table existing (`20260929140000_admin_analytics_bundle_fix_uid_ambiguity.sql` lines 201–208).

---

## 4. Proposed activation funnel and event taxonomy

### 4.1 Activation funnel (recommended stages)

| Stage | Definition | Measurable today? | Event / SQL needed |
|-------|------------|-------------------|---------------------|
| 1. Signup | `auth.users` / `profiles.created_at` | **Yes** | — |
| 2. Onboarding complete | `profiles.onboarding_completed = true` | **Yes** | — |
| 3. First account | `min(accounts.created_at)` | **Partial** | Milestone RPC or materialized view |
| 4. First trade | `min(trades.created_at)` | **Partial** | Same |
| 5. Return visit (D1) | Activity on day after signup | **No** | Daily user activity snapshot |
| 6. Regular active | e.g. ≥4 active weeks in first 8 | **No** | WAU-style rollup per user |

**Abandonment:** Without step timestamps (beyond profile flags), you can only infer **stuck users** with SQL such as “signup &gt;7d, onboarding_completed false” or “onboarding true, zero trades” — **batch queries**, not live funnel.

### 4.2 Minimal event taxonomy (do not implement yet)

Store in Supabase (recommended): **`product_events`** (or `analytics_events`) append-only:

| Event name | Properties (non-PII) | Platforms |
|------------|----------------------|-----------|
| `signup_completed` | `signup_flow_source`, `platform` | web, ios |
| `onboarding_completed` | `duration_ms` optional | web, ios |
| `account_created` | `account_category` | web, ios |
| `trade_created` | `import_source` enum, `is_first` bool | web, ios |
| `broker_connect_started` / `_succeeded` / `_failed` | `provider`, `error_code` | web, ios |
| `feed_opened` | — | web, ios |
| `message_sent` | `conversation_type` dm/room | web, ios |
| `subscription_active` | `source` stripe/apple | server-only |
| `walkthrough_completed` / `_dismissed` | `tour_id`, `version` | web, ios |

**Server-side milestones (preferred for money paths):** Emit from existing API routes / RPC wrappers (Stripe webhook, broker sync success) to avoid client tampering.

**Background vs real users:** Tag events with `origin: user | server | cron | worker`; exclude `worker` and `service_role` from DAU/MAU. DAU should use **`product_events`** or a **`daily_user_activity`** rollup, not raw trade inserts from broker sync (filter `import_source` / `trigger` metadata where applicable).

### 4.3 Lightweight architecture (reuse Supabase)

1. **Table:** `product_events (id, user_id, name, occurred_at, platform, props jsonb, origin)` + RLS insert own row; service role for server events.
2. **Nightly rollup job** (Vercel cron or Supabase `pg_cron`): populate `daily_user_activity (user_id, day, event_bitmap or counts)`.
3. **Admin RPC extension:** `admin_analytics_bundle_v2` adding MAU, cohort retention, funnel conversion — **reads rollups only** (keep admin page fast).
4. **Optional:** Mirror critical counters to existing `admin_analytics_bundle` for backward compatibility.

**Do not** send full trade/financial payloads to third parties unless required; keep aggregates in-house.

---

## 5. Recommended admin analytics dashboard

Extend **`/admin/analytics`** (and iOS admin consumer) with:

| Section | Metrics |
|---------|---------|
| **Growth** | Total users, signups/day, MAU, WAU, DAU, DAU/MAU |
| **Retention** | D1/D7/D30 cohort curves (signup week cohorts) |
| **Activation** | Funnel conversion signup → onboarding → first account → first trade (7d window) |
| **Engagement** | DAU breakdown by event source (journal, social, messaging, rooms) |
| **Monetization** | Pro users (Stripe + Apple), trial, churned subs (from `profiles` + `apple_subscriptions`) |
| **Features** | Broker connected users, AI messages/week, vault items, tax exports/week |
| **Quality** | Open support/feedback (already present) |

**Fix existing RPC/UI gaps:**

- Chart **`activeUsersPerDay`, `reelsPerDay`, `commentsPerDay`, `likesPerDay`** (already in RPC JSON).
- Implement real **`followsPerDay`** or remove placeholder zeros.

---

## 6. Current production observability coverage

### 6.1 Web and Vercel

| Signal | Coverage | Evidence | Gap |
|--------|----------|----------|-----|
| Unhandled exceptions | **Partial** | Sentry if `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN` set | Optional; not guaranteed |
| API route failures | **Partial** | Sentry `onRequestError`, route `console.error` | No centralized API metrics dashboard in repo |
| Slow endpoints | **Partial** | Sentry 10% traces; Vercel Speed Insights (consent) | No p95 SLOs defined |
| Cron success | **Partial** | Cron routes return JSON; **no external alert** | `vercel.json` crons |
| Deployment errors | **Unknown** | Vercel UI (out of repo) | — |
| Client logging | **Low in prod** | `devLog` no-op in production | `lib/devLog.ts` |

### 6.2 Supabase

| Signal | Coverage | Evidence |
|--------|----------|----------|
| DB errors/timeouts | **Unknown** | No `pg_stat_statements` automation in repo |
| Realtime disconnects | **Partial** | iOS Realtime lifecycle logs; web ad hoc |
| Auth failures | **Partial** | Client errors; no aggregate |
| RPC failures | **Partial** | Client/user errors; Backend V2 dev telemetry only |
| Storage failures | **Partial** | Upload errors surfaced to user |
| RLS denials | **Unknown** | Not centrally logged |

Use **Supabase Dashboard** + advisors (not wired in CI/docs).

### 6.3 Native iOS

| Signal | Coverage | Evidence |
|--------|----------|----------|
| Crashes | **Unknown / likely gap** | `native-ios/ARCHITECTURE.md` says pick Crashlytics or Sentry — **no Sentry init found in Swift grep** |
| Network errors | **Good (local)** | `NetworkClient` + `RetryPolicy`, `UserFacingError` offline |
| Reconnect | **Good** | `SupabaseReconnectRepairCoordinator`, Realtime logs |
| Memory / hangs | **Unknown** | No Instruments automation in repo |
| DEBUG probes | **Good** | `SessionNetworkProbe`, `FeedLoadProbe`, etc. |

### 6.4 Critical integrations

| Integration | Logging | Alerting | Notes |
|-------------|---------|----------|-------|
| Tradovate sync | **Structured JSON** | **None in repo** | `tradovateSyncLogger.ts`, worker stdout |
| Rithmic | Route errors | None | Vercel 120s limit |
| Stripe webhooks | `console.error`, verbose affiliate logs | None | Returns 200 on many handler failures |
| Entitlements | API + DB | None | Client poll after checkout |
| APNs | `[apns] accepted/rejected` | None | Invalid token cleanup |
| Financial RPCs | Postgres exceptions to client | None | e.g. `delete_prop_payout` |

### 6.5 Logging quality and secrets

| Finding | Severity | Evidence |
|---------|----------|----------|
| Prod errors use `console.error` / Sentry | Medium | Stripe webhook, broker sync |
| Dev-only verbose logs | Good | `devLog` |
| APNs token redaction | Good | `apns.ts` comment |
| Stripe affiliate **TEMP** console logs in webhook | Medium | `invoice.paid` handler — noisy, may include ids |
| No log retention policy in repo | Unknown | Platform defaults |

### 6.6 Correlation across platforms

**No shared trace id** from iOS → Supabase → Vercel found. **Cannot** easily tie one user’s client session to a specific API route failure without manual Sentry + user id search.

---

## 7. Critical monitoring and alerting gaps

| Gap | Severity | Who knows today? | Impact |
|-----|----------|------------------|--------|
| No paging/on-call for worker down | **High** | Users see “Worker offline”; ops may not | Broker auto-sync stopped |
| Stripe webhook silent failure (200 OK) | **High** | Affected users; finance if unpaid | Wrong Pro state |
| Supabase outage | **High** | Users; maybe Sentry spike | Total outage |
| Cron failure (weekly reports, stories) | **Medium** | Only if Vercel cron UI checked | Degraded features |
| APNs delivery failures | **Medium** | Logs only | Missed notifications |
| iOS crash visibility | **Medium** | Unknown without SDK | Blind to native stability |
| Platform-wide vs user error | **Medium** | Manual | Slow incident detection |

---

## 8. Recommended lightweight monitoring architecture

**Principles:** Early-stage cost, reuse **Sentry + Supabase + Vercel**, no heavy APM unless needed.

| Layer | Recommendation | Complexity |
|-------|----------------|------------|
| **Errors** | Require `SENTRY_DSN` in production; tag `platform=web|ios`; separate projects optional | S |
| **iOS crashes** | Wire **one** of Sentry/Crashlytics per ARCHITECTURE.md | M |
| **Uptime** | External ping on `/` + critical API (`/api/billing/entitlement` health-style) | S |
| **Broker worker** | Alert if `listener_worker_heartbeat_at` stale &gt; 5m for any connected Tradovate user (SQL check cron → email/Slack webhook) | M |
| **Stripe** | Alert on webhook 5xx rate; **fix 200-on-failure**; Stripe Dashboard failed webhooks | M |
| **Crons** | Vercel cron failure notifications (built-in) + log `ok: false` | S |
| **Supabase** | Enable report email; weekly review advisors; optional Logflare drain | S |
| **Product health** | Daily SQL job: signups, DAU, broker error rate, sync partial rate → Slack | M |

**Correlate:** Pass `X-Request-Id` from iOS `NetworkClient` on BFF calls; include in Sentry breadcrumbs.

Priorities align with [INFRASTRUCTURE audit §13](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md): billing, broker sync, auth, data integrity.

---

## 9. Technical debt findings (ranked by severity)

| Rank | Finding | Severity | Platform | Evidence | Impact |
|------|---------|----------|----------|----------|--------|
| 1 | **Backend V2 dual-path** (REST + RPC behind 15 flags) | **High** | Web (+ iOS flags) | `lib/backendV2/flags.ts`, `docs/backend-v2/README.md` | Two behaviors in prod; bugs fixed twice |
| 2 | **Oversized web Client Components** | **High** | Web | `community/page.tsx` ~5728 LOC, `profile/[id]/page.tsx` ~4649, `messages/[id]/page.tsx` ~4683, `feed/page.tsx` ~3313 | Regression risk, hard onboarding |
| 3 | **Large RPC/bootstrap surface** | **High** | Supabase | 100+ `rpc_v1_*` / `rpc_v2_*` migrations | Contract drift web/iOS |
| 4 | **Admin analytics incomplete vs RPC** | **Medium** | Web admin | Follows series zeros; reels/comments/likes not charted | Misleading ops view |
| 5 | **DAU definition vs product reality** | **Medium** | Analytics | `DAU_DEFINITION`, SQL unions | Undercount passive users |
| 6 | **Web Realtime channel sprawl** | **Medium** | Web | Prior audit + feed page | Complexity vs iOS RealtimeHub |
| 7 | **Full trade history on Trades/Analyst** | **Medium** | Web | `fullHistory: true` on trades/analyst pages | Perf + cache complexity |
| 8 | **Stripe webhook handler structure** | **Medium** | Vercel | `webhook/route.ts` | Resilience + maintainability |
| 9 | **Contextual tour state device-local** | **Low–Med** | Web+iOS | `contextualTour/progressStore.ts` | Cannot measure walkthrough in admin |
| 10 | **DEBUG-only network probes** | **Low** | iOS | `SessionNetworkProbe` | No prod perf visibility |

**Not counted as debt (by instruction):** Large file size alone where bounded and stable; GRDB shadow path is intentional with flags OFF in Release.

---

## 10. Top 10 highest-value improvements

| # | Improvement | Area | Impact | Effort | Confidence |
|---|-------------|------|--------|--------|------------|
| 1 | **`product_events` + daily rollups + MAU/retention admin RPC** | Analytics | Growth decisions | **L** | High |
| 2 | **Activation funnel SQL/RPC** (signup → first trade) | Analytics | Focus onboarding | **M** | High |
| 3 | **Fix Stripe webhook HTTP semantics + entitlement poll** | Observability + billing | Revenue correctness | **M** | High (see infra audit) |
| 4 | **Broker worker heartbeat alert** | Observability | Core sync | **S** | High |
| 5 | **Require Sentry DSN + iOS crash SDK** | Observability | Stability | **M** | High |
| 6 | **Complete admin analytics charts + fix follows series** | Analytics | Ops trust | **S** | High |
| 7 | **Enable Backend V2 bootstraps incrementally; remove REST duplicates** | Tech debt | Maintainability | **L** | Medium |
| 8 | **Split largest web pages (community, profile, messages) by route-owned data** | Tech debt | Velocity | **L** | Medium |
| 9 | **Server-side walkthrough milestones** (optional sync of dismiss/complete) | Analytics | Onboarding UX | **S** | Medium |
| 10 | **Expand DAU inputs** (messages, room_messages, optional `last_seen_at`) | Analytics | Retention accuracy | **M** | Medium |

Effort key: **S** = days, **M** = 1–2 weeks, **L** = multi-sprint.

---

## 11. Estimated implementation complexity

| Recommendation | Complexity | Dependencies |
|----------------|------------|--------------|
| product_events table + RLS + insert helper | M | Migration, client/server helpers |
| Nightly rollup cron | M | Cron secret, idempotent SQL |
| admin_analytics_bundle_v2 | M | Rollups populated |
| Funnel RPC | S–M | Milestone definitions |
| Sentry iOS | M | Xcode config, DSN |
| Worker heartbeat alert | S | SQL + Slack webhook |
| Stripe webhook 5xx fix | S | Stripe retry behavior test |
| Admin chart parity | S | UI only |
| Backend V2 flag rollout | L | QA per screen |
| Page splits | L | Careful realtime/cache ownership |

---

## 12. Recommended implementation order

1. **Observability quick wins:** Sentry DSN enforced, broker heartbeat check, Stripe webhook status codes (parallel infra audit fixes).
2. **Trust existing metrics:** Fix follows placeholder + chart unused RPC series (admin page).
3. **Foundation table:** `product_events` + server events for signup, onboarding, broker sync, subscription.
4. **Rollups + MAU/retention** in admin (read-only dashboards before client event flood).
5. **Client events** for feed open, messaging, walkthrough (minimal set).
6. **Backend V2 cutover** one flag at a time (reduces duplicate logic debt).
7. **Large page decomposition** when touching those areas for other reasons (avoid rewrite-for-rewrite).

---

## Appendix A — Evidence index

| Topic | Path |
|-------|------|
| Admin analytics RPC | `supabase/migrations/20260929140000_admin_analytics_bundle_fix_uid_ambiguity.sql` |
| Admin client | `lib/adminAnalytics.ts`, `app/admin/analytics/page.tsx` |
| DAU definition | `DAU_DEFINITION` in `lib/adminAnalytics.ts` |
| User directory | `lib/adminUsersDirectory.ts`, `app/admin/users/page.tsx` |
| Vercel web analytics | `app/components/NativeAwareVercelInsights.tsx` |
| Backend V2 telemetry | `lib/backendV2/telemetry.ts` |
| Feature flags | `lib/backendV2/flags.ts` |
| Getting Started signals | `rpc_v1_getting_started_signals` migrations |
| Walkthrough storage | `lib/contextualTour/progressStore.ts`, `lib/contextualTour/catalog.ts` |
| Sentry web | `lib/sentry.ts`, `sentry.server.config.ts` |
| Tradovate logs | `lib/integrations/tradovate/tradovateSyncLogger.ts` |
| iOS network retry | `native-ios/.../Retry/RetryPolicy.swift` |
| iOS admin analytics | `DefaultAdminUsageAnalyticsRepository.swift` |
| Prior perf/debt context | [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) |
| Resilience/billing | [INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md) §13 |

---

## Appendix B — Finding format reference

Each prioritized item in §9–§10 includes: **severity**, **platform**, **evidence path**, **user/business impact**, **recommended fix**, and **confidence** (High = code-confirmed, Medium = strong inference, Low = needs production data).

---

*End of report.*
