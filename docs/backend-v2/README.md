# Backend V2 — Web + iOS Performance Program

Canonical index for the Backend V2 rollout. Each phase doc states what is **implemented**, **unit-tested**, **manually validated**, **benchmarked**, **externally blocked**, **inferred**, or **not measured**.

**Scope:** Next.js web + native iOS share Supabase RPC contracts behind feature flags (default OFF).  
**Non-goals in cleanup:** No SQL/RPC/RLS changes from this documentation pass.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for shared infrastructure.

---

## Phase index

| Phase | Topic | Status | Doc |
|-------|--------|--------|-----|
| A | RPC optimization foundations | Implemented | [PHASE_A_RPC_OPTIMIZATION.md](./PHASE_A_RPC_OPTIMIZATION.md) |
| B1 | Route prefetch ownership | Implemented + unit-tested | (see `lib/routePrefetch.test.ts`) |
| B2 | Feed optimization | Implemented | [PHASE_B2_FEED_OPTIMIZATION.md](./PHASE_B2_FEED_OPTIMIZATION.md) |
| C | Cold start | Implemented + unit-tested | [PHASE_COLD_START_OPTIMIZATION.md](./PHASE_COLD_START_OPTIMIZATION.md) |
| C | Messages optimization | Implemented | [PHASE_C_MESSAGES_OPTIMIZATION.md](./PHASE_C_MESSAGES_OPTIMIZATION.md) |
| C | Hardening | Implemented | [PHASE_C_HARDENING.md](./PHASE_C_HARDENING.md) |
| D | Web loading / skeletons | Implemented + unit-tested | [PHASE_D_WEB_LOADING.md](./PHASE_D_WEB_LOADING.md) |
| 2 | Session bootstrap RPC | Implemented + unit-tested; flag OFF by default | [PHASE2_SESSION_BOOTSTRAP.md](./PHASE2_SESSION_BOOTSTRAP.md) |
| 2.5–2.6 | Session cleanup / duplicate bootstrap | Implemented + unit-tested | [PHASE2_5_SESSION_CLEANUP.md](./PHASE2_5_SESSION_CLEANUP.md), [PHASE2_6_DUPLICATE_BOOTSTRAP.md](./PHASE2_6_DUPLICATE_BOOTSTRAP.md) |
| 3 | Dashboard bootstrap | Implemented + unit-tested | [PHASE3_DASHBOARD_BOOTSTRAP.md](./PHASE3_DASHBOARD_BOOTSTRAP.md) |
| 4 | Feed bootstrap | Implemented + unit-tested | [PHASE4_FEED_BOOTSTRAP.md](./PHASE4_FEED_BOOTSTRAP.md) |
| 4.75 | Ownership cleanup | Implemented | [PHASE4_75_OWNERSHIP_CLEANUP.md](./PHASE4_75_OWNERSHIP_CLEANUP.md) |
| 5 | Feed cutover | Implemented + unit-tested | [PHASE5_FEED_CUTOVER.md](./PHASE5_FEED_CUTOVER.md) |
| 5.1–5.2 | Critical path / duplicate audit | Implemented | [PHASE5_1_CRITICAL_PATH.md](./PHASE5_1_CRITICAL_PATH.md), [PHASE5_2_DUPLICATE_AUDIT.md](./PHASE5_2_DUPLICATE_AUDIT.md) |
| 6 | Messaging bootstrap | Implemented + unit-tested | [PHASE6_1_MESSAGING_WIRING_AUDIT.md](./PHASE6_1_MESSAGING_WIRING_AUDIT.md) |
| E | Profile bootstrap | Implemented + unit-tested | [PHASE_E_PROFILE.md](./PHASE_E_PROFILE.md), [PHASE_E2_PROFILE_TAIL_LATENCY.md](./PHASE_E2_PROFILE_TAIL_LATENCY.md) |
| E | Getting Started signals | Implemented + contract-tested | [PHASE_E_GETTING_STARTED.md](./PHASE_E_GETTING_STARTED.md) |
| F | Room bootstrap | Implemented + unit-tested | [PHASE_F_ROOM_BOOTSTRAP.md](./PHASE_F_ROOM_BOOTSTRAP.md) |
| F2 | Community Realtime | Implemented + unit-tested | [PHASE_F2_COMMUNITY_REALTIME.md](./PHASE_F2_COMMUNITY_REALTIME.md) |
| G | Conversation thread bootstrap | Implemented + unit-tested | [PHASE_G_CONVERSATION_THREAD_BOOTSTRAP.md](./PHASE_G_CONVERSATION_THREAD_BOOTSTRAP.md) |
| H1 | Prop Firm bootstrap | Implemented + unit-tested | [PHASE_H1_PROP_FIRM_DASHBOARD_AUDIT.md](./PHASE_H1_PROP_FIRM_DASHBOARD_AUDIT.md) |

---

## Reel media (web, post–Phase H)

| Area | Idle cards | Intentional playback |
|------|------------|----------------------|
| Profile | `ReelIdlePoster` — image or static placeholder | `ReelViewer` → `DetailModalVideo` |
| Feed | `ReelThumbnailPreview` → `ReelIdlePoster` | `FeedReelDetailModal` → `DetailModalVideo` |
| Trades (linked reel) | `TradeReelAttachment` / `ReelThumbnailPreview` → `ReelIdlePoster` | Trade/Feed detail modals |
| Upload / compose | N/A | `captureReelVideoThumbnail(file)` — **local File only** |

**Removed (confirmed dead):** `ReelVideoPosterFrame`, `ReelNativeVideoThumb`, browser `captureReelPosterFromUrl` for idle cards.

**Regression tests:** `npm run test:reel-media` (Profile + Feed idle invariants).

---

## Feature flags (15)

All default **OFF**. Env keys use `NEXT_PUBLIC_BACKEND_V2_*`. Tests isolate via `lib/backendV2/flags.testIsolation.ts` (no dependency on developer `.env.local`).

`session`, `dashboard`, `feed`, `profile`, `messages`, `messageThreads`, `rooms`, `roomPresence`, `activity`, `calendar`, `explore`, `leaderboard`, `tradeDetail`, `settings`, `propFirm` (15 total).

---

## Test commands

| Command | Purpose |
|---------|---------|
| `npm run test:backend-v2` | Contract decode, flags, bootstrap modules, community realtime, profile, cold start |
| `npm run test:reel-media` | Idle Reel poster + Feed media invariants |
| `npm run test:phase-h1` | Prop Firm route ownership |
| `npm run test:phase-h2` | Request ownership (Phase H2) |
| `npm run test:phase-h3` | Reels-by-trade cache + affiliate sync classification |

Benchmark scripts under `scripts/benchmark-*.mjs` require env (`BENCHMARK_USER_JWT`, etc.) and **skip** when unset — they do not print JWTs.

---

## Network / latency claims

- **Unit-tested:** contract shapes, cache keys, single-flight, viewer isolation, flag parsing.
- **Manually validated:** Reel idle cards (HAR: zero video bytes before click on Profile; Feed requires intentional open).
- **Benchmarked:** only when `scripts/benchmark-*.mjs` run with credentials (not CI by default).
- **Externally blocked:** Production Stripe Connect sync when deploy env keys mismatch connected accounts.
- **Inferred / not measured:** pool wait time, exact production cold-start request counts in [WEB_SUPABASE_PERFORMANCE_AUDIT.md](../WEB_SUPABASE_PERFORMANCE_AUDIT.md) (static audit, Aug 2026).

See also [NETWORK_OWNERSHIP_AUDIT.md](./NETWORK_OWNERSHIP_AUDIT.md).
