# TradeTraxs — Viral Growth Readiness Audit

**Date:** 2026-10-24  
**Mode:** Read-only — no code changes, builds, tests, load simulations, or deployments.  
**Scenario:** ~**10,000 new registrations within 24 hours** (TikTok / Instagram virality), with first-day activity modeled as stated below.  
**Related audits:** [INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md), [FEED_CONCURRENCY_COST_FRAGILITY_AUDIT_2026-10-24.md](./FEED_CONCURRENCY_COST_FRAGILITY_AUDIT_2026-10-24.md), [PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md](./PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md), [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md).

**Legend:** **Verified** = traced in repo/migrations. **Assumption** = reasonable viral scenario, not measured in production. **Platform unknown** = Supabase/Vercel/Tradovate plan limits not in repo.

---

## Final deliverables (executive)

### 1. Overall viral-growth readiness assessment

**Moderate readiness for signups; weak readiness for simultaneous social + broker load on a single Supabase project without headroom monitoring.**

- **Registration path** is mostly **client-driven** (Supabase Auth + `ensureProfileForUser` + `/onboarding`) — no app-owned signup queue. Supabase Auth and Postgres must absorb **~10k auth users + ~10k profile rows** in 24h (**Verified** flow; **Platform unknown** Auth SMTP/rate ceilings).
- **Core journal** (accounts, trades, RLS, free-plan triggers with advisory locks) is **designed for correctness under concurrency** more than for **10k/day marketing spikes** (**Verified** migrations; pool/compute limits **Platform unknown**).
- **Social Feed** concentrates load into **`rpc_v1_feed_bootstrap`** plus **heavy Realtime fan-out on Web** (**Verified** — see Feed audit). A subset of viral users opening Feed the same hour behaves like a **mini thundering herd**.
- **Tradovate auto-sync** is a **single-worker, one-WebSocket-per-connection** design (**Verified** `docs/tradovate/BROKER_SYNC_WORKER.md`). **2,000 new OAuth connections in 24h** is operationally plausible but **stressful** for one worker and Tradovate-side limits (**Assumption** on broker API).
- **Observability / alerting** is **thin** for a founder waking up to 10k signups: optional Sentry, Vercel Analytics, Supabase dashboard — **no in-repo paging/runbooks** (**Verified** observability audit).
- **Billing:** Standard web signup sets **free intent** (`beginStandardFreeSignup` → `setSignupIntent("free")` in `app/login/LoginPageClient.tsx`). **`onboarding_completed === true` grants app access** without checkout (`isSubscriptionExempt` in `lib/subscriptionAccess.ts`) when monetization enforcement is off (**Verified**). Legacy checkout gates apply only when `?next=checkout` (**Verified**).

**Confidence:** Behavioral paths **high**. Absolute capacity, dollars, and “what breaks first” ordering **medium-low** without live metrics.

### 2. Likely first five bottlenecks (viral day)

| Order | Bottleneck | Why it surfaces on viral day |
|-------|------------|------------------------------|
| 1 | **Supabase Postgres compute + connection pool** | Burst of Auth, profile inserts, session/dashboard/feed RPCs, trade writes — many independent clients (**Verified** architecture). |
| 2 | **`rpc_v1_feed_bootstrap` + Realtime subscribe storm** | Thousands of Feed opens → 1 RPC/user + up to **~5 Realtime channels/user on Web Following** (**Verified** Feed audit). |
| 3 | **Storage egress + upload bandwidth** | 1k creators × images/reels → object storage growth and uncached public GETs (**Verified** no transform CDN in `lib/optimizedStorageImage.ts`). |
| 4 | **Tradovate sync worker (SPOF) + Vercel long broker routes** | 2k OAuth connects → up to **2k WS** on **one** worker instance; manual/full sync hits **120s** serverless (**Verified**). |
| 5 | **Email + notification side effects** | Auth confirmation emails, onboarding admin notify (`/api/admin-notify/beta-signup`), engagement notifications + APNs (**Verified** routes; provider limits **Platform unknown**). |

### 3. Estimated infrastructure pressure (first 24h)

Uses **scenario assumptions** from the user brief; HTTP counts are **order-of-magnitude** from verified call patterns.

| Workload | Assumed volume | Verified request / work pattern | Rough pressure (Assumption) |
|----------|----------------|----------------------------------|-----------------------------|
| Registrations | 10,000 | Auth signup + `ensureProfileForUser` (select + insert) + `profiles` AFTER INSERT → `notification_preferences` row | **~20k–40k** PostgREST calls; **10k** auth.users rows |
| Onboarding complete | 5,000 | Profile UPDATE + possible `rpc_v1_session_bootstrap` on next app open | **~5k–15k** writes + bootstrap RPCs |
| Trading accounts | 3,000 | `accounts` INSERT + free-plan trigger (`pg_advisory_xact_lock` per user) | **~3k** inserts; lock contention if same user hammers create (**Verified** trigger) |
| Trade import | 2,000 | CSV: `consume_app_rate_limit('csv_import')` **10/hour/user**; broker: sync RPC/API + worker | **Rate-limited** per user on CSV (**Verified**); broker **heavy** |
| Feed browse | 4,000 | `rpc_v1_feed_bootstrap` (limit 8 Web / 20 iOS) + Realtime | **~4k–8k** RPCs; **~4k** WS clients if concurrent |
| Media upload | 1,000 | Storage PUT + metadata rows + possible transcode paths for reels | **100s of GB-month** storage if reels dominate (**Assumption** on mix) |

**Not double-counted:** Realtime connections scale with **concurrent** sessions, not 10k registrations alone.

### 4. Cost exposure (realistic scenarios — no invented plan tiers)

All **$ ranges are illustrative** only; **current Supabase/Vercel/Resend/APNs/Tradovate billing tiers are not in the repo**.

| Scenario | Cost drivers | Exposure |
|----------|--------------|----------|
| **Signup-heavy, low engagement** | Auth MAU, DB storage (profiles), minimal egress | Likely **modest** vs social/broker spike |
| **4k Feed + 1k uploads** | DB compute, Realtime connections, **storage + egress** for images/reels | **Egress often dominates** when thumbnails/video are hot (**Verified** serving model) |
| **2k broker connects + sync** | Worker host 24/7, Vercel **GB-seconds** on 120s imports, Tradovate API | Worker + function duration; **not** visible in repo pricing |
| **OpenAI** (if many use Trade Analyst) | `gpt-4o` per analyze route | **Unbounded** if viral users hit AI (**Verified** as expensive action in infra audit) |

**First limits approached (typical managed stacks — Platform unknown):** Realtime concurrent connections, Postgres CPU, Storage egress, Vercel function concurrency/duration, email send rate.

### 5. Highest-risk features under virality

1. **Web Feed Realtime + insert hydration** (N+1 REST on events).  
2. **Tradovate worker single instance** + token refresh on many connections.  
3. **Leaderboard API** full public trade scan on cache miss (attracts curious new users).  
4. **Stripe webhook “always 200”** on handler failures (entitlement drift if many convert to paid mid-spike).  
5. **Client profile insert setting `is_pro: true`** while DB default/trigger path was changed to default false — **`profile_is_pro_user()` treats `is_pro` as Pro for DB limits** (**Verified** code + SQL; see §1 Registration).  
6. **Admin onboarding emails** — up to **5k Resend messages** if every completion notifies founder (**Verified** route).

### 6. Emergency response checklist

See **§8** (full plan). Immediate: Supabase **Database health, Auth, Realtime, Storage**, Vercel **5xx/latency**, worker **heartbeat**, Stripe dashboard, **egress** graph.

### 7. Top five preventative improvements (worth doing now)

1. **Align signup `is_pro` with product intent** — stop client insert from granting DB-level Pro bypass (`ensureProfileForUser` vs `20261007200000_profiles_signup_no_automatic_is_pro.sql` + `profile_is_pro_user`).  
2. **Supabase capacity playbook** — compute upgrade path, pooler settings, Realtime connection budget; define **SLO alerts** (even manual weekly drill).  
3. **Broker sync scaling** — second worker only with **distributed locking** (docs already warn scale=1); queue/defer **initial full sync** after OAuth.  
4. **Feed Web Realtime consolidation** — reduce channels per tab (iOS RealtimeHub pattern).  
5. **Protect founder + cost** — gate or batch admin signup emails; **storage lifecycle** on reels; optional **AI rate limits** on analyze routes.

---

## 1. Registration surge

### 1.1 Can Supabase Auth handle thousands of registrations?

**Platform unknown** for hard Auth QPS. **Verified:** All standard paths call `supabase.auth.signUp` / OAuth from `app/login/LoginPageClient.tsx` (email) and parallel OAuth handlers — **no application-level signup queue or worker**.

**Verified email path:** After signup, if no session user, UI shows *“Check your email to confirm…”* (`LoginPageClient.tsx`). If **email confirmation is required** in the Supabase project, **only confirmed users** get a session — viral signups may **stall in Auth** until SMTP throughput catches up (**Platform unknown** SMTP limits).

**Verified OAuth:** Google/Apple flows call the same **`ensureProfileForUser`** after auth (`webSocialOAuthPolicy` / login client patterns).

### 1.2 Email verification, OAuth, onboarding

| Step | Behavior | Evidence |
|------|----------|----------|
| Profile shell | **`ensureProfileForUser`** — idempotent select/insert; handles `23505` race | `lib/ensureProfileForUser.ts` |
| Referral | `referred_by` + `/api/referral-attribution` backfill; beta codes ignored | same file + `isBetaReferralRef` |
| Free vs checkout | **`beginStandardFreeSignup()`** sets intent **free**; checkout only if `?next=checkout` | `LoginPageClient.tsx` |
| Next route | **`resolveSignupProfileSetupPath()` → `/onboarding`** | `lib/signupFlow.ts` |
| App access after onboarding | **`onboarding_completed === true` → `isSubscriptionExempt`** | `lib/subscriptionAccess.ts`, `lib/profileOnboardingGate.ts` |
| Monetization gates | **`app_monetization_settings`** fail-closed defaults (paywall off) | `lib/monetizationConfig.ts` |

### 1.3 Database triggers, profile creation, welcome flows

**Verified on each new `profiles` row:**

- **`profiles_ensure_notification_preferences`** — AFTER INSERT inserts `notification_preferences` (`20260626170000_notification_preferences.sql`).
- **Beta referral trigger** — only if `referred_by` matches closed beta codes (`profiles_apply_beta_from_referred_by`).
- **Automatic Pro grant trigger** — **removed/paused**; column default **`is_pro = false`** (`20261007200000_profiles_signup_no_automatic_is_pro.sql`).

**Mismatch (high impact):** Client **`ensureProfileForUser` still inserts `is_pro: true`** on create (`lib/ensureProfileForUser.ts` lines 156–166). Privileged-field protection is **BEFORE UPDATE**, not INSERT (`profiles_reject_privileged_self_update`). **`profile_is_pro_user()` returns true when `is_pro` is true**, bypassing free-plan account/trade/post/messaging DB limits when `free_plan_limits_enforced()` is on (`20260706100000_free_plan_daily_limits.sql`, `20261007230000_free_plan_total_accounts_and_trade_slots.sql`).

**Welcome / notify:** Onboarding completion can trigger **`notifyAdminBetaSignup`** → **`POST /api/admin-notify/beta-signup`** (deduped via `beta_signup_notified_at`). **5,000 completions ≈ up to 5,000 admin emails** if Resend is configured — not rate-limited in app (**Verified**).

**No DB trigger** was found that auto-creates `profiles` from `auth.users` without client insert — profile creation is **application-driven** (**Verified** from migration search + client code).

### 1.4 Signup rate limits and abuse protections

| Control | Scope | Verified limits |
|---------|--------|-----------------|
| Supabase Auth | Signup/sign-in | **Platform unknown** (built-in abuse / CAPTCHA / email rate) |
| Engagement writes | likes, comments, follows | e.g. **60 likes/min**, **30 follows/hour** (`20260703190000_beta_launch_p1_hardening.sql`) |
| Messaging | DMs / room messages | **12 DMs / 10s**, **500/hour** (`20260718090000_phase1_messaging_scalability.sql` overrides burst rules) |
| CSV import | per user | **`csv_import` / `csv_upload`: 10/hour** via `consume_app_rate_limit` + triggers |
| Creator codes | redeem | **`redeem_creator_access_code`** — `FOR UPDATE`, idempotent same-user (`20260713200000_fix_creator_redeem_race.sql`) |
| BFF rate limits | selected API routes | `lib/server/durableUserRateLimit.ts` → `rate_limit_counters` |

**Legitimate users blocked?**

- **Unlikely on signup itself** unless Supabase Auth or email provider throttles (**Platform unknown**).
- **Possible on social/import** if power users hit **`rate_limit_hit`** exceptions on likes/comments/messages/CSV (**Verified** — errors surfaced via `lib/userFacingError.ts` / `rate_limit_exceeded`).
- **Free plan** raises **`FREE_PLAN_ACCOUNT_LIMIT`** after **3 accounts** when enforcement on (**Verified**).

---

## 2. First-day user activity model

### 2.1 Scenario inputs (Assumption — user brief)

| Metric | Count |
|--------|------:|
| New registrations | 10,000 |
| Complete onboarding | 5,000 |
| Create trading accounts | 3,000 |
| Import trades | 2,000 |
| Browse Feed | 4,000 |
| Upload posts/images/clips | 1,000 |

### 2.2 Database requests (order-of-magnitude)

**Method:** Per-user patterns from code × volume. Ranges account for shell bootstrap and pagination.

| Activity | Verified per-user pattern | Est. PostgREST/RPC (24h) |
|----------|---------------------------|-------------------------|
| Signup + profile | 1–3 Auth + 2–4 REST | **25k–70k** |
| Onboarding | 1–3 profile/settings writes | **5k–15k** |
| Session / dashboard first open | `rpc_v1_session_bootstrap`, dashboard/analytics RPCs (15–22 calls cited in WEB audit for cold app) | **Assumption:** 50% of onboarded open app → **25k–110k** if cold |
| Accounts ×3k | INSERT + possible bootstrap refresh | **3k–10k** |
| Imports ×2k | CSV gated 10/h; broker sync heavy (100s–1000s rows) | **Highly variable** — **2k–20k+** writes to trades/executions |
| Feed ×4k | **1× `rpc_v1_feed_bootstrap`** (+ optional following fetch) | **4k–8k** RPCs |
| Uploads ×1k | Storage + posts/reels rows | **1k–5k** metadata writes |

**Realtime (concurrent, not cumulative):** If **10%** of Feed browsers are online together → **400** clients × **~5 channels** ≈ **2,000** logical channels on Web Following (**Assumption** + **Verified** channel count).

### 2.3 Serverless executions (Vercel)

**Verified:** ~100 API routes; viral users hit **push register**, **notifications**, **broker OAuth/callback**, **import/sync** (`maxDuration` up to **120s** on broker paths — infra audit).

**Assumption:** 2k broker connects might drive **2k–6k** long-running function invocations (OAuth + initial sync), dominating **GB-seconds** and concurrency.

### 2.4 Storage growth and media bandwidth

**Verified:** Public/object URLs; **no Supabase image transform CDN** in app config.

**Assumption (illustrative):**

- 700 image posts × ~2 MB ≈ **1.4 GB** stored.  
- 300 short reels × ~15 MB ≈ **4.5 GB** stored.  
- Feed browse: 4k users × ~8 thumbnails × ~200 KB ≈ **6 GB egress** if caches cold (repeat views multiply).

### 2.5 Distinction summary

| Item | Type |
|------|------|
| RPC names, rate limit numbers, worker architecture, free-plan triggers | **Verified** |
| Concurrent online fraction, media sizes, broker sync duration | **Assumption** |
| Supabase Auth max signups/hour, exact Realtime connection cap | **Platform unknown** |

---

## 3. Broker integration surge (~2,000 connections in 24h)

### 3.1 Tradovate

**Verified:**

- OAuth on **Vercel**; **auto-sync only on** `services/tradovate-sync-worker/run.ts` (**not Vercel** — `BROKER_SYNC_WORKER.md`).
- **One WebSocket per connected OAuth connection**; deploy docs say **start one worker instance** unless distributed locking is added.
- Heartbeat stale **>90s** → UI “Worker offline” (`TRADOVATE_WORKER_HEARTBEAT_STALE_MS`).
- Canonical sync **`syncTradovateBrokerAccount()`** shared with manual Sync Now; debounced **1.5s** coalesce on props events.

**Under 2k new connections (Assumption):**

- Worker must **authenticate and subscribe 2k sessions** — CPU/memory/network on worker VM; **Tradovate connection limits unknown**.
- **Token renewal** failures → stale listener until refresh path succeeds (**Verified** integration tables + worker logs pattern).
- **Initial full sync** after connect can run **large REST** from worker/Vercel — overlaps with viral DB write load.

### 3.2 Queue, throttle, dedupe

**Verified patterns (infra + migrations):** Sync locking, **`broker_lifecycle_id`** / execution uniqueness (infra audit §13) — **duplicate trades unlikely** if constraints hold. **No global fair-queue** across users for sync — **each mapping** syncs on events/manual action.

**Rithmic:** Runs on **Vercel** up to **120s** — many parallel imports **contend for function concurrency** (**Verified**).

### 3.3 Partial histories and recovery

**Verified:** Failed sync leaves **last good snapshot**; manual **Sync Now** retries same canonical function. **Auto-recovery** depends on worker health + valid tokens — **not** a guaranteed background retry queue for all failure modes.

---

## 4. Social platform surge

### 4.1 Feed at thousands of users

**Verified (Feed audit):** Production Feed uses **`backendV2.feed` default ON** → **`loadFeedBootstrapForUser` → `rpc_v1_feed_bootstrap`** (`FEED_PAGE_SIZE = 8` Web). **Single-flight only per user/tab**, not global.

**4,000 Feed opens in 24h** spread out is **moderate**; **hundreds opening within minutes** reproduces the **1,000 concurrent** analysis: pool wait, RPC latency, Realtime join storm.

### 4.2 Likes, follows, comments, notifications, messages

**Verified:**

- Writes hit **`rate_limit_hit`** on triggers (production caps in `20260703190000` + messaging burst in `20260718090000`).
- **`notifications` INSERT** restricted from authenticated clients; fan-out via **service role** / `NotificationService` (**Verified** messaging scalability migration comments).
- Push via **APNs** from server routes.

**Risk:** Viral creators receive **notification storms** (likes/comments/follows) → **DB rows + serverless + APNs**; preferences gate via `should_deliver_notification` (**Verified** trigger exists).

### 4.3 Realtime subscription scale

**Verified:** Web Feed Following → **up to 5 channels** per tab; chunking for **>100** following IDs (`REALTIME_IN_FILTER_MAX_IDS`). **iOS RealtimeHub** dedupes topics vs Web’s multiple channels.

**Platform unknown:** Supabase Realtime **max concurrent connections** for the project tier.

### 4.4 Video / image cost

**Verified:** Idle Feed cards avoid loading full video bytes (Backend V2 reel program). **Full reel watch + upload** drives **storage + egress**; **no CDN layer in repo**.

---

## 5. Financial and billing systems

### 5.1 Free registration vs legacy gates

**Verified:**

- Standard signup → **free intent** + **onboarding**; **`isSubscriptionExempt`** includes **`onboarding_completed`** — **no Stripe required** for core access.
- **`needsSubscriptionCheckout`** false once onboarding complete unless profile incomplete.
- **`app_monetization_settings`** defaults fail-closed (enforcement off unless DB says otherwise).

### 5.2 Creator / access codes under concurrency

**Verified:** `redeem_creator_access_code` uses **row lock**, idempotent **same user**, **`exhausted` vs `invalid`** (`20260714010000_creator_redeem_exhausted_vs_invalid.sql`). Service-role only from **`app/api/creator/redeem/route.ts`**.

### 5.3 Stripe webhooks and races

**Verified:** Webhook route returns **`200 OK`** on many inner failures (infra audit). Client **`syncMembershipAfterStripeCheckout`** polling partially mitigates checkout races.

**Viral relevance:** Low if most stay **free**; **spikes if influencer promo drives TraxPro trials** simultaneously.

### 5.4 Duplicate financial submissions

**Verified:** Prop/payout and broker paths use **RPC constraints / idempotency keys** in migrations (infra audit). **Not immune** to client double-submit everywhere — highest confidence on **broker execution uniqueness** and **creator redeem**.

---

## 6. Infrastructure and cost (spike-only)

**Do not treat as quotes.** Use Supabase/Vercel dashboards during an incident.

| Resource | Spike signal | Repo evidence |
|----------|--------------|---------------|
| Postgres CPU | Slow RPCs, pool timeouts | Many bootstraps + feed RPC |
| Realtime | Connection count, join latency | Feed + notifications + messages |
| Storage | Total GB + egress GB | Uploads + Feed images |
| Vercel functions | Duration p95, concurrent executions | Broker OAuth/sync, notifications, AI |
| Worker VM | CPU, restarts, stale heartbeats | Tradovate WS count |
| Third-party | OpenAI invoice, Resend, Stripe | Analyze-trade, admin emails, conversions |

**Approached first (typical):** **Realtime connections** and **Postgres CPU** during **evening peak Feed**; **egress** if reel traffic goes viral; **Vercel concurrency** if broker import race.

---

## 7. Failure scenarios

### 7.1 What breaks first?

**Most likely (Assumption + Verified architecture):**

1. Postgres **latency / pool wait** (503-style errors from PostgREST).  
2. **Feed load failures** / empty states (RPC timeout).  
3. **Realtime delayed** — app feels stale.  
4. **Tradovate “Worker offline”** if worker OOM/crash under connection count.  
5. **Email confirmation backlog** (Auth UX).

### 7.2 Database saturated

**Verified:** No circuit breakers in app. Clients show user-facing errors (`toUserFacingErrorMessage`). **iOS** has offline-oriented patterns; **Web** relies more on caches (infra audit).

**Data loss:** Trades/financial records **protected by FK + uniqueness** on broker paths; **unlikely wholesale loss** — **partial sync** or **failed writes with user-visible errors** more plausible.

### 7.3 One expensive operation degrades all

**Yes — shared Postgres.** Examples: **leaderboard cache miss**, **heavy broker sync**, **admin analytics bundle**, **`rpc_v1_trades_owner_rows` full history** (infra audit).

### 7.4 Owner alerts

**Verified:** Optional **Sentry** (~10% traces), **Vercel Analytics/Speed Insights**, Supabase logs/advisors (if checked manually). **No automated founder pager** in repo. **Admin analytics** (`admin_analytics_bundle`) is **manual admin UI**, not real-time viral signup tracking (`followsPerDay` hardcoded 0 in observability audit).

### 7.5 Automatic recovery

**Partial:** Realtime reconnect (iOS repair paths); Stripe client reconciliation; broker **manual Sync Now**. **No auto-scale worker** in repo; **no DB read replica** logic in app.

---

## 8. Emergency response plan (founder playbook)

### 8.1 Monitor immediately (first 2 hours)

1. **Supabase Dashboard:** Database CPU, memory, connections, **Realtime connections**, **Auth** signups/errors, **Storage egress**.  
2. **Vercel:** 5xx rate, function **duration/concurrency**, top routes (`/api/integrations/*`, `/api/notifications/*`, `/api/stripe/*`).  
3. **Tradovate worker logs:** `worker_started`, `connection_authenticated`, heartbeat updates; cross-check in-app **Listener connected**.  
4. **Stripe / Resend / OpenAI** dashboards if checkout or emails or AI spike.  
5. **Sentry** (if enabled) for error rate regressions.

### 8.2 Infrastructure upgrades to prepare

- **Supabase:** Larger compute or **disk**; confirm **connection pooler** (Supavisor) for PostgREST; Realtime add-on if connection-bound (**Platform unknown** SKUs).  
- **Vercel:** Pro/Enterprise concurrency if broker routes throttle.  
- **Worker:** Larger VM or **temporary second instance only if locking implemented** (otherwise duplicate WS risk — **Verified** docs warn).  
- **CDN / caching** for static media (architectural — not flip-a-switch in repo).

### 8.3 Temporarily reduce nonessential workloads

| Lever | Effect |
|-------|--------|
| Disable **`NEXT_PUBLIC_BACKEND_V2_DUAL_RUN`** | Dev-only double fetch — ensure off in prod (**Verified**) |
| Reduce **admin signup emails** | Disable Resend key or patch route to sample (ops — not in repo switch) |
| Pause **weekly trading report cron** / **stories cron** | `vercel.json` crons — lowers background load |
| **Feature flags:** turn off optional Realtime watches | `lib/realtimePublicationPolicy.ts` patterns |
| **Defer AI analyze** | Env/route kill switch if one exists; otherwise rate limit at edge (ops) |
| Communicate **“Sync Now later”** if worker overloaded | Manual sync still works when worker healthy |

### 8.4 Protect core trading journal

1. Prioritize **Postgres availability** over Feed polish.  
2. Steer support to **manual trade entry** if CSV/import rate-limited (**10/hour** — **Verified**).  
3. Avoid running **leaderboard** marketing links until cache warm.  
4. Watch **free-plan triggers** — users should see clear errors, not silent drops (`FREE_PLAN_ACCOUNT_LIMIT`).

### 8.5 Prevent surprise bills

1. Set **billing alerts** on Supabase, Vercel, OpenAI, cloud worker host (**Platform** consoles).  
2. Watch **Storage egress** daily during spike.  
3. Cap or throttle **AI** and **video upload** if abuse appears.

### 8.6 If Supabase or Vercel is unhealthy

**Supabase degraded:**

- Status page + support ticket with **project ref** (`fobudrkniacatvilbofw` in loadtest guard — **Verified**, do not load-test prod).  
- Reduce Realtime: ask users to use **iOS** or **refresh single tab**; disable social browsing messaging temporarily.  
- Scale compute; kill heavy **admin** queries.

**Vercel degraded:**

- Broker **OAuth callback** failures — pause marketing CTAs to “connect broker”.  
- Push/register and webhooks may lag — monitor **Stripe** for retry queue.

**Communications:** Status via social/email; in-app banner if deployable quickly (ops).

---

## Appendix A — Key code references

| Topic | Location |
|-------|----------|
| Signup + profile | `app/login/LoginPageClient.tsx`, `lib/ensureProfileForUser.ts` |
| Free access gate | `lib/subscriptionAccess.ts`, `lib/profileOnboardingGate.ts` |
| Feed bootstrap | `lib/feedContent.ts`, `lib/feedBootstrapRepository.ts`, `app/(app)/feed/page.tsx` |
| Rate limits | `supabase/migrations/20260703190000_beta_launch_p1_hardening.sql`, `20260718090000_phase1_messaging_scalability.sql` |
| Free plan accounts | `supabase/migrations/20261007230000_free_plan_total_accounts_and_trade_slots.sql` |
| Creator redeem | `supabase/migrations/20260713200000_fix_creator_redeem_race.sql`, `app/api/creator/redeem/route.ts` |
| Broker worker | `docs/tradovate/BROKER_SYNC_WORKER.md`, `services/tradovate-sync-worker/run.ts` |
| Stripe webhook | `app/api/stripe/webhook/route.ts` |
| Backend V2 defaults | `lib/backendV2/flags.ts` |
| Load test guard (no prod load test) | `loadtest/README.md` |

---

## Appendix B — What this audit did not do

- No production metrics, Supabase MCP plan lookup, or live load tests.  
- No verification of **Auth hook** configuration in Supabase Dashboard (email confirm, CAPTCHA, redirect URLs).  
- No Tradovate **contractual rate limits** — treat as **Platform unknown**.

---

*End of report.*
