# Phase D — Web Loading Optimization (HAR 10)

**Status:** Code prepared in-repo. **Not applied to production SQL.** HAR re-capture required to claim request-count improvements.

---

## HAR 10 baseline (provided)

| Metric | Value |
|--------|-------|
| Total requests | 126 (`/` → login → dashboard → trades → feed → messages) |
| Transferred | ~1.22 MB |
| JavaScript | 58 req / ~510 KB |
| Supabase Storage | 15 req / ~292 KB |
| Images (other) | 9 req / ~334 KB |
| RSC | 17 req / ~25 KB |
| Supabase REST (data) | 8 (16 entries incl. 8 OPTIONS) |

### Critical slow paths (HAR 10)

| Request | ~Duration | Root cause (confirmed) |
|---------|-----------|------------------------|
| `rpc_v2_messaging_bootstrap` | 404 @ 2.64s | **V2 migration not applied** to connected DB |
| V1 messaging fallback | 0.99s | Expected after V2 miss |
| Notification PATCH | 1.68s | Serial after V2 404 probe (pre-fix) |
| Feed bootstrap RPC | 8.58s | **Likely unoptimized DB function** — apply `20260820224542_rpc_v1_feed_bootstrap_optimize.sql` on staging and benchmark |
| Reels by trade IDs | 10.18s | **Heavy embed** `PROFILE_REELS_SELECT` + RLS on joined trades |
| Copy-trading groups | 5.00s | **Trades page loaded on mount for all Pro users** |
| Screenshot Storage (×5) | ~4.5s each | **Full object URLs** in list cards |
| favicon.ico (×6) | ~106 KB | Re-fetched per navigation; no immutable cache |
| Hero 1080 + 1920 | ~206 KB+ | `sizes="100vw"` + broad deviceSizes |
| Vercel analytics scripts | 404 | Loaded on local `next start` |

---

## Route-by-route request ownership map

### `/` (marketing homepage)

| Request type | Owner | Blocking? | Cache | Notes |
|--------------|-------|-----------|-------|-------|
| RSC / document | Next.js `(marketing)/page.tsx` | Yes | ISR 86400s | Static shell + Suspense loaders |
| Featured trades | `LandingFeaturedTradesSectionLoader` → `getCachedLandingFeaturedTrades` | No (streamed) | `unstable_cache` 30m | **Server-only** — not in browser HAR |
| Reviews | `LandingTestimonialsSectionLoader` | No | `unstable_cache` | Server-only |
| Hero image | `LandingPageClient` Next/Image | LCP | Browser + `/_next/image` | Was dual 1080/1920 |
| JS bundles | Root layout providers | Hydration | `_next/static` | UserProfileProvider mounts on `/` (existing) |
| Supabase client tables | Should be **zero** on anonymous `/` | — | — | Auth session discovery only via provider |

### `/login`

| Request | Owner | Notes |
|---------|-------|-------|
| RSC | `login/page.tsx` + redirects | Multiple RSC from layout + auth shell |
| Session | Supabase auth (if cookie) | Not app-table fan-out |
| Prefetch | `routePrefetch` secondary | B1 already reduced profile prefetches |

### `/dashboard`

| Request | Owner | Notes |
|---------|-------|-------|
| Session RPC | `loadSessionBootstrapForUser` | 1× when V2 ON |
| Dashboard RPC | `loadDashboardBootstrapForUser` | 1× when V2 ON |
| Copy groups | `useCopyTradingGroups` | **On-demand only** (dashboard) |
| Realtime | `UserProfileProvider` / notifications | 1 WS when warm path allows |
| Trades/accounts cache | `useCachedTrades/Accounts` | Session cache |

### `/trades`

| Request | Owner | Notes |
|---------|-------|-------|
| Trades + accounts | `useAppDataCache` | Cached session |
| Copy groups | `useCopyTradingGroups` | **Fixed:** on-demand (picker / copy-group filter) |
| Reels | `fetchReelsByTradeIds` in `trades/page.tsx` | Visible trade IDs only; **fixed:** `REEL_ROW_SELECT` |
| Screenshots | `TradesPageTradeCard` | **Fixed:** `TradeScreenshotPreview` transform 640w |

### `/feed`

| Request | Owner | Notes |
|---------|-------|-------|
| Feed RPC | `loadFeedBootstrapForUser` | 1×; **8.58s → apply feed optimize migration** |
| Profile prefetches | `ProfileLink` / `routePrefetch` | B1 reduced; no profile viewport prefetch in feed cards |

### `/messages`

| Request | Owner | Notes |
|---------|-------|-------|
| Messaging V2 | `MessagingRpcBootstrapRepository` | 404 when migration missing |
| V1 fallback | Same repository | After 2.64s probe (pre-fix) |
| PATCH notifications | `markMessageNotificationsRead` | Serial when V2 missing |
| **Fix:** session cache | `messagingV2Availability.ts` | Skip V2 probe after first miss |

---

## Implemented optimizations (Phase D)

### Task 1 — Messages fallback waterfall
- `lib/backendV2/messagingV2Availability.ts` — sessionStorage flag after first V2-missing error
- Repository goes straight to V1 when cached; clears flag on successful V2
- Does **not** treat auth errors as missing-RPC
- **Deploy:** `20260821014228_rpc_v2_messaging_bootstrap.sql` on staging/production for 1-RPC inbox

### Task 2 — Feed 8.58s RPC
- **No new SQL in Phase D** (per instruction)
- **Required migration:** `supabase/migrations/20260820224542_rpc_v1_feed_bootstrap_optimize.sql`
- Benchmark: `node scripts/benchmark-feed-rpc.mjs` after apply
- HAR 8.58s strongly suggests **pre-optimization function** still deployed

### Task 3 — Reels 10.18s
- `fetchReelsByTradeIdsOnce` now uses `REEL_ROW_SELECT` only (no trades embed / hydrate)
- Index exists: `reels_trade_id_idx` (`20260701120000_reels_trade_link.sql`)
- Still one bounded `.in("trade_id", visibleIds)` per visible page

### Task 4 — Copy-trading on Trades
- Mirrored dashboard pattern: `copyGroupsRequested` + `isCopyGroupFilterValue(accountFilter)`
- Wired `onAccountPickerOpen={requestCopyGroups}` to web + native filter sheet

### Task 5 — Screenshot thumbnails
- New `TradeScreenshotPreview` — Supabase render URL `trade-thumb` @ 640w
- Full URL preserved for lightbox via `onImageClick`

### Task 6 — Homepage hero
- `sizes="(max-width: 768px) 100vw, 1920px"`
- `deviceSizes: [640, 828, 1200, 1920]` in `next.config.ts`
- Server queries already cached via `landingServerData.ts`

### Task 7 — JS bundles
- No new splits in Phase D (avoid speculative churn)
- Run `npm run build` for route First Load JS table
- Bundle analyzer optional: `@next/bundle-analyzer` not added (build output sufficient for baseline)

### Task 8 — RSC / prefetch
- No global prefetch disable; existing B1 guards retained
- Further RSC dedupe needs HAR 11 per-route capture

### Task 9 — Favicon + analytics
- `Cache-Control: immutable` headers for `/favicon.ico` and `/logo.png`
- `NativeAwareVercelInsights` — loads only when `VERCEL` / `*.vercel.app`

### Task 10 — Provider shell
- No layout split in Phase D (high regression risk)
- `shouldWarmAppDataCachesForPath` already gates dashboard warm on marketing/auth

---

## Files changed

- `lib/backendV2/messagingV2Availability.ts` (new)
- `lib/backendV2/messagingBootstrapRepository.ts`
- `lib/backendV2/messagingRpcCompat.ts`
- `lib/reels.ts`
- `app/(app)/trades/page.tsx`
- `app/components/TradesPageMainContent.tsx`
- `app/components/TradesPageTradeCard.tsx`
- `app/components/ui/TradeScreenshotPreview.tsx` (new)
- `app/components/platform/native/NativeIosTradesFilterSheet.tsx`
- `app/components/LandingPageClient.tsx`
- `app/components/NativeAwareVercelInsights.tsx`
- `next.config.ts`
- `lib/coldStart.test.ts`, `lib/phaseD.test.ts` (new)
- `package.json`

---

## Tests / build

- `npm run test:backend-v2` — **143 pass**
- `npm run build` — **pass**

---

## Production rollout order

1. Deploy **web app** (Phase D client fixes — safe immediately)
2. Apply **`20260821014228_rpc_v2_messaging_bootstrap.sql`** on staging → verify 1 inbox RPC
3. Apply **`20260820224542_rpc_v1_feed_bootstrap_optimize.sql`** on staging → benchmark feed
4. Capture HAR 11 per route (cold + warm) with checklist from spec
5. Production SQL during low-traffic window after staging sign-off

---

## Remaining bottlenecks

1. Feed RPC until optimize migration applied
2. Root layout mounts full provider tree on marketing routes
3. Provider split / marketing layout isolation (future phase)
4. HAR-measured RSC count per navigation (needs clean captures)
5. Full bundle analyzer pass for homepage/login chunk attribution

---

## Confirmations

- **native-ios/** — untouched
- **Auth, RLS, FreePlan, UI, routing** — preserved
- **No SQL applied to production**
- **No claimed HAR improvements** without re-measurement
