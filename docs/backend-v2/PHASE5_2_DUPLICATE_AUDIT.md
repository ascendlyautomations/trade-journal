# Backend V2 Phase 5.2 — Duplicate Request Ownership Audit

**Status:** Duplicate elimination on Login → Dashboard idle. **No new RPCs / ownership changes.**

**Date:** 2026-08-19

---

## Objective

Every piece of data is fetched **once** by its owner, reused via shared caches, then patched by Realtime.

---

## Duplicate request table (login → Dashboard idle)

| Request | Count (before) | Callers | Owner | Dup class | Root cause | Action |
|---------|----------------|---------|-------|-----------|------------|--------|
| `rpc_v1_session_bootstrap` | 1 | UserProfileProvider | Session | A | Single-flight | Keep |
| `rpc_v1_dashboard_bootstrap` | 1 | warm + ensureTrades + ensureAccounts | Dashboard | A (coalesced) | Shared flight/cache | Keep |
| `admin_users` REST | 0–1 | Navbar deferred / account menu | Session | **C/D** | Cache-paint race → REST before Session | **Removed** — Session subscribe only |
| notifications unread HEAD | 0–1 | Navbar 2.5s fallback | Session | **C/D** | Badge REST fallback | **Removed** when Session ON |
| `get_conversation_unread_counts` stack | 0–1 | Navbar DM fallback | Session | **C/D** | Same fallback | **Removed** when Session ON |
| `followers` REST | 0–1 | Getting Started if Session late | Session | **D** | GS raced Session | **Wait** for Session cache before GS |
| trades HEADs (GS) | 0 | GS when Dashboard cache warm | Dashboard | E | Already cache-aware | Keep |
| `profile_posts` HEAD | 1 | Getting Started | Onboarding | A (domain leftover) | Not in Session | Keep 1× (owner) |
| `room_members` | 1 | Getting Started | Onboarding | A (domain leftover) | Not in Session | Keep 1× (owner) |
| `/api/early-access/status` | 1–2 | Navbar GS entry + TraxsProForLifeCard `refresh()` | Onboarding/EA | **B/G** | Card force-refresh on mount | **Removed** mount refresh |
| settings accounts warm | 0 net | dataPrefetch deferred | Dashboard | **E/G** | Redundant when Dash ON | **Skipped** when Session+Dash ON |
| Copy Trading | 0–2 | Dashboard after deferred | Copy Trading | A | Intentional lazy | Keep |
| Feed / stories / reels | 0 | — | Feed | — | Not on this path | — |
| StrictMode double GS | 0–2 | GettingStartedProgressProvider | Onboarding | **B/G** | No cancel / no coalesce | **Fixed** cancel + in-flight |

---

## Special investigations

| Item | Verdict |
|------|---------|
| admin_users | **Bug/race** when Session ON — fixed |
| room_members | **Expected** Onboarding probe (1×) |
| followers | **Cache miss race** — fixed via Session wait |
| notifications | **Legacy fallback** — removed when Session ON |
| conversation unread | **Legacy fallback** — removed when Session ON |
| profile_posts | **Expected** Onboarding (until onboarding RPC) |
| reels / stories | **Not on login→Dashboard path** |
| trade lookups | Dashboard RPC only (+ optional fullHistory for >500 trades) |
| accounts / trades | One Dashboard RPC; ensure* are cache consumers |

---

## Files modified

- `app/components/Navbar.tsx` — Session-only badges + admin; no REST fallback when Session ON
- `app/components/dashboard/TraxsProForLifeCard.tsx` — drop mount `refresh()`
- `lib/dataPrefetch.ts` — skip secondary warm when Session+Dashboard ON
- `lib/GettingStartedProgressProvider.tsx` — wait for Session; cancel deferred; coalesce in-flight

---

## Counts (flags ON, typical cold login → Dashboard idle)

| | Before 5.2 | After 5.2 |
|--|------------|-----------|
| Session RPC | 1 | 1 |
| Dashboard RPC | 1 | 1 |
| Navbar admin/badge REST | 0–2 (race) | **0** |
| EA status | 1–2 | **0–1** |
| GS probes | 1–2× (StrictMode) | **1×** (`profile_posts` + `room_members`) |
| Secondary prefs/accounts warm | noop / noise | **skipped** |

**Estimated request reduction:** ~1–4 REST/API calls per login (races + EA double + StrictMode GS).  
**Estimated latency:** Less contention on critical path; badges/admin no longer compete with Session/Dashboard.

---

## Remaining intentional (not duplicates)

- Onboarding: `profile_posts` + `room_members` (future onboarding bootstrap)
- Copy Trading when Pro + deferred UI
- Realtime notification channel → badge refresh on events (not bootstrap)
- Full-history trades REST only if Dashboard window `history_complete=false` (>500 trades)

---

## Recommendation

**Yes — ready to continue with Profile RPC.** Session / Dashboard / Feed ownership is clean on the login→Dashboard path; remaining probes are domain leftovers (Onboarding), not ownership bugs.
