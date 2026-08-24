# Backend V2 — Phase 4.75 Global Request Elimination & Ownership Cleanup

**Status:** Ownership cleanup only. **No new SQL / migrations / RPCs / repositories.**

**Date:** 2026-08-19

---

## Goal

Every remaining Supabase request has **exactly one owner**, is fetched **once**, cached appropriately, and thereafter updated by **Realtime** when possible.

This is the last large optimization/cleanup pass before continuing domain bootstraps.

---

## What this phase changed (code)

| Change | Why |
|--------|-----|
| Removed achievements from `warmAppDataCaches` | Achievements → Profile/Achievements domain (lazy) |
| Feed prefers `getSessionFollowingIds` before `followers` REST | Session owns following graph |
| Getting Started reuses Session following count + Dashboard trades cache | Onboarding consumes Session/Dashboard; no duplicate trade/follow probes |
| InputTradeForm / QuickTradeModal → `ensureAccountsLoaded` + Session profile | Dashboard owns accounts; Session owns plan slice |
| Copy Trading process cache + invalidate on mutate | Copy Trading domain — not Dashboard |
| TraxsProForLifeCard: drop 30s polling | Focus refresh only until Onboarding/EA Realtime |

---

## Special-case decisions

### 1. `get_conversation_unread_counts` / DM badges

**Correct path:** Messaging domain computes unread → Session stores **badge aggregate** (`badges.dm_unread`) → Navbar/shell **reads Session only** → Realtime patches Session badges.

- Navbar must **not** own the unread stack when Session is warm.
- Per-conversation unread stays Messaging (inbox / thread), never Dashboard.
- Do **not** put DM unread into Dashboard bootstrap.

### 2. Copy Trading

**Correct owner:** **Copy Trading domain** (future `rpc_v1_copy_trading_bootstrap` when needed).

- **Not** Session (not universal; Pro-gated; mutable memberships).
- **Not** Dashboard (Dashboard only needs account selector metadata when CT UI is shown).
- Account selector **consumes** Copy Trading cache; Dashboard does not own it.
- This phase: shared in-memory cache + single-flight so Dashboard/Input/QuickTrade do not triple-fetch.

### 3. Calendar

Calendar is a **pure consumer** of the Dashboard trades dataset (props). No independent cold history fetch on Dashboard calendar. Keep it that way.

### 4. Trade Input

Accounts → Dashboard cache (`ensureAccountsLoaded`). Plan/`is_pro` → Session/UserProfile when warm. Free-plan lock/CSV fields may still need one profiles GET until Settings/Onboarding owns those fields.

### 5. Getting Started / Onboarding

Checklist signals belong to **Onboarding domain**. Today they **reuse** Session (profile flags, following) + Dashboard (trades) and only probe Onboarding-specific leftovers (`profile_posts` HEAD, `room_members`). Future: `rpc_v1_onboarding_bootstrap` — do not fold into Dashboard.

### 6. Achievements

Cold warming **eliminated**. Load on Profile/Achievements tab open only.

---

## Final ownership map

```
Session
  viewer profile slice
  badges (notifications_unread, dm_unread)
  following_ids
  prefs_min
  entitlement (is_admin, is_pro, …)

Dashboard
  trades dataset
  accounts dataset
  equity / metrics / analytics derived client-side

Feed
  feed items + authors + engagement + stories (+ cursor)

Messaging
  conversations, previews, per-conversation unread
  (feeds Session badge aggregate; does not live in Dashboard)

Copy Trading
  groups + memberships (account selector metadata)

Profile
  public/own profile header + tabs (trades/posts/reels/achievements)

Rooms
  rooms list + memberships + room detail

Onboarding
  checklist probes (posts, rooms joined) + early-access progress

Activity
  notifications inbox feed

Settings
  editable profile / preferences / lock fields / CSV cooldown

Auth
  onAuthStateChange / session lifecycle only
```

---

## Request counts (web, typical path)

| Scenario | Count | Notes |
|----------|------:|-------|
| Legacy cold login (all V2 flags OFF) | ~14–22 | REST fan-out + warmers |
| After Phase 4.75, flags ON, login → Dashboard idle | **~3–6** | Session + Dashboard (+ optional Copy Trading / Onboarding if UI shown) |
| + Feed idle (flags ON) | **+1** | Feed bootstrap |
| Target after remaining domain RPCs | **2 shell + 1/screen** | Same as Phase 4.5 |

### Intentionally kept (this phase)

- `rpc_v1_session_bootstrap`
- `rpc_v1_dashboard_bootstrap`
- `rpc_v1_feed_bootstrap`
- Copy Trading groups fetch **when CT UI enabled** (domain-owned, now cached)
- Getting Started `profile_posts` / `room_members` when checklist visible
- Early-access progress on focus (no interval)
- Realtime channels (not counted as REST)

### Eliminated / moved this phase

- Achievements cold warm
- Feed duplicate `followers` when Session warm
- Getting Started followers HEAD + trade HEADs when caches warm
- Input/QuickTrade parallel accounts REST (and Pro profiles GET when Session warm)
- Copy Trading multi-mount fan-out (shared cache)
- Early-access 30s poll

---

## Estimates

| Metric | Estimate |
|--------|----------|
| Request reduction (login→Dashboard idle, flags ON) | **~40–60%** vs pre-4.75 warmers/duplicates |
| Disk IO reduction | Proportional to fewer REST table scans (achievements, followers HEAD, accounts duplicates) |
| Latency | Fewer critical-path round-trips on Input/Feed following; Navbar already Session-badge short-circuit |

---

## Remaining Backend V2 roadmap

1. **Profile** bootstrap  
2. **Messaging home** (+ conversation detail) — Session badges stay aggregates only  
3. **Activity** inbox  
4. **Rooms** home / room  
5. **Explore / Leaderboard**  
6. **Copy Trading** bootstrap (replace REST cache)  
7. **Onboarding** bootstrap (GS + early access)  
8. **Settings** delta (lock fields, prefs edits)  
9. Detail screens (trade/post) as needed  

Rule for all future work: **one owner, one fetch, Realtime thereafter.** No God RPCs. No Dashboard dumping foreign domains.
