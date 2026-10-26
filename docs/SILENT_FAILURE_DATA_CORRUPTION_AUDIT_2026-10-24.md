# TradeTraxs — Silent Failure & Hidden Data Corruption Audit

**Date:** 2026-10-24  
**Mode:** Read-only — no code changes, builds, tests, simulators, or deployments.  
**Main question:** What can silently go wrong without displaying an error or notifying anyone?  
**Related:** [DEPENDENCY_REGRESSION_FRAGILITY_AUDIT_2026-10-24.md](./DEPENDENCY_REGRESSION_FRAGILITY_AUDIT_2026-10-24.md), [PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md](./PRODUCT_ANALYTICS_OBSERVABILITY_TECH_DEBT_AUDIT_2026-10-24.md), [INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md](./INFRASTRUCTURE_SCALABILITY_COST_AUDIT_2026-10-24.md).

**Legend:** **Confirmed** = behavior verified in source. **Potential** = plausible from architecture; not proven as an active production bug. **Theoretical** = edge case with mitigations elsewhere.

---

## Executive summary

TradeTraxs **surfaces many user-facing errors** on critical paths (manual trade insert, reel video upload failure, free-plan blocks). The largest **silent** gaps cluster around:

1. **Broker trade persistence** — per-lifecycle insert/update failures are **skipped without failing the sync** (`persistBrokerTrades.ts`).  
2. **Read-path error masking** — owner trade RPC helpers return **`null` / `[]` instead of errors** (`tradeOwnerRead.ts`).  
3. **Client caches** — Web `appDataCache` and iOS GRDB/analytics flags can show **confident UI with incomplete or stale numbers**.  
4. **Billing webhooks** — many handler failures still return **HTTP 200** to Stripe (`stripe/webhook/route.ts`).  
5. **Background systems** — worker offline, push skips, notification `ok: true, skipped`, cron JSON with no paging.

**Financial / journal severity:** Items **#1–#8** in the ranked list below deserve the most attention.

---

## 1. Top 20 potential silent failures (ranked by severity)

| Rank | Issue | Status | User notice? | Financial / data impact |
|------|--------|--------|--------------|-------------------------|
| 1 | **Broker lifecycle persist `continue` on failed insert/update** | **Confirmed** | Unlikely — sync may report success / partial counts | **Missing or stale trades, wrong P&L** |
| 2 | **`rpcTradeOwnerRead` / RPC error → `null`** | **Confirmed** | “Save failed” on some paths; other callers may treat as missing | Trade appears unsaved or hidden |
| 3 | **`rpcTradesOwnerRows` → `{ rows: [], error: null }` when payload not array** | **Confirmed** | Empty lists without error | **Under-counted stats, reports** |
| 4 | **Dashboard / analytics on incomplete history (`INITIAL_TRADES_LIMIT`, `historyComplete` flags)** | **Confirmed** | Looks “fine” until full history loaded | **Wrong win rate, P&L, streaks** |
| 5 | **`trade_daily_stats` vs journal desync** (revision not refetched on Web) | **Potential** | Charts disagree with Trades | **Incorrect analytics** |
| 6 | **Shallow cache merge** (`mergeTradesInCache`, `upsertTradeInCache`) | **Confirmed** | Partial fields until refresh | Wrong P&L/ticker in UI |
| 7 | **Broker partial sync success** (`IMPORT_SUCCESS_PARTIAL`, `syncLockStatus: partial`) | **Confirmed** | Depends on UI surfacing `import_partial` | Incomplete account history |
| 8 | **Stripe webhook inner failure → still `200 OK`** | **Confirmed** | User thinks they are Pro | **Billing / entitlement drift** |
| 9 | **Trades persisted with `pnl: null` / numeric ticker** (broker financials) | **Confirmed** counters | Trade rows exist | Misleading performance metrics |
| 10 | **`ensureProfileForUser` referral backfill fails silently (prod)** | **Confirmed** | None | Attribution only — not journal |
| 11 | **`ensureProfileForUser` inserts `is_pro: true`** vs DB default false | **Confirmed** code | None if limits off | **Free-limit bypass** when enforcement on |
| 12 | **Prefetch warm `.catch(() => [] \| null)`** | **Confirmed** | Empty dashboard, no toast | Missing data until navigation retry |
| 13 | **Psychology report: RPC empty → fallback to capped dashboard rows** | **Confirmed** | Report looks complete | **Incomplete psychology dataset** |
| 14 | **Prop firm expense row dropped by `mapExpenseRow` → null** | **Confirmed** | Row missing from UI/export | **Tax export omits bad rows silently** |
| 15 | **Tax CSV period / kind filters** (`buildPropFirmTaxCsv`, `buildExpenseTrackerCsv`) | **Confirmed** by design | User chose period; no warning for out-of-range rows | **Export excludes** out-of-period records |
| 16 | **Reel: video OK, thumbnail fails → uses video URL as thumb** | **Confirmed** | Cosmetic | Orphan storage **Potential** |
| 17 | **Tradovate worker offline** (no WS) — auto-sync stops | **Confirmed** docs | “Worker offline” if user opens Settings | Stale journal until manual sync |
| 18 | **OAuth `reconnect_required` stored but user never reconnects** | **Confirmed** status | Only if user visits integrations | Sync silently stopped |
| 19 | **Realtime disconnect** (Feed / rooms) without user-visible error | **Potential** | Stale social counts | No journal loss |
| 20 | **Push: `ok: true, skipped: preferences` / APNs not configured** | **Confirmed** patterns | No push | No data loss |

---

## 2. Confirmed defects vs theoretical risks

### 2.1 Confirmed (code evidence)

| ID | Finding | Evidence |
|----|---------|----------|
| C1 | Per-trade broker upsert failures swallowed | `lib/integrations/tradovate/persistBrokerTrades.ts` — `if (error \|\| !inserted) continue`; update path increments only `if (!error)` |
| C2 | Owner read RPC masks errors | `lib/tradeOwnerRead.ts` L21: `if (error \|\| data == null) return null` |
| C3 | Owner rows RPC empty success | `lib/tradeOwnerRead.ts` L39–40: non-array → `{ rows: [], error: null }` |
| C4 | Warm prefetch swallows load failures | `lib/dataPrefetch.ts` L38–42 `.catch(() => null)` / `.catch(() => [])` |
| C5 | Stripe affiliate branch exits 200 without fixing profile | `app/api/stripe/webhook/route.ts` L663 `return new Response("OK", { status: 200 })` when no `customerId` |
| C6 | Stripe subscription update errors logged only | Same file L1234–1240, L1249 always 200 outer path for handled events |
| C7 | Psychology journal degrades to dashboard cap | `lib/psychology/reports/journalTrades.ts` L113: `(rows.length ? rows : capped)` |
| C8 | Invalid expense rows filtered out | `lib/propFirmExpenses.ts` L466–468 `.filter(... mapExpenseRow ...)`; L614–618 returns null for bad type |
| C9 | Manual trade save fails loudly on insert | `lib/saveManualTrade.ts` L270–277 — **not silent** (contrast) |
| C10 | Public post after trade save fails loudly | `lib/saveManualTrade.ts` L306–313 returns `ok: false, code: "post"` |
| C11 | Broker execution dedupe index | `supabase/migrations/20260915140000_broker_execution_user_fill_identity.sql` — duplicates **theoretical** at trade level if persist skips |
| C12 | Notification handlers return success when skipped | `lib/server/notifications/NotificationService.ts`, handlers with `{ ok: true, skipped: true }` |

### 2.2 Potential / theoretical

| ID | Finding | Why potential |
|----|---------|---------------|
| P1 | iOS GRDB analytics cache serves stale aggregates | Release flags enable GRDB-first paths (`BackendV2FeatureFlags.swift`); Web lacks same repair defaults |
| P2 | Feed bootstrap cache never invalidated on trade edit | `lib/backendV2/feedBootstrapCache.ts` — Realtime patches only |
| P3 | Concurrent Web + iOS edit last-write-wins | No CRDT; standard Postgres `UPDATE` |
| P4 | `profileSplitMirrorWrites` partial failure | Dual-write without transaction across tables (`lib/profileSplitMirrorWrites.ts`) |
| P5 | Cron job partial failure invisible to founder | `weekly-trading-reports/route.ts` returns JSON only — no in-repo alerting |
| P6 | Duplicate broker trades | Mitigated by `broker_lifecycle_id` unique partial index; undermined if C1 skips insert but executions link inconsistently |

---

## 3. Section findings (investigation areas)

### 3.1 Silent data loss

| Scenario | Verdict | Details |
|----------|---------|---------|
| Manual trade fails to save | **Usually loud** | Insert error → user message (`saveManualTrade.ts`) |
| Trade disappears after refresh | **Potential** | Cache showed prepend; DB insert failed on different device; or C1 broker skip |
| Broker skips executions | **Confirmed partial** | Reconstruction may omit fills; persist loop **continues** on write error (C1) |
| Media partial upload | **Confirmed** | Reels: upload fails → error returned; thumbnail optional after video (`lib/reels.ts` L681–692, L692 `resolvedThumbnailUrl ?? videoUpload.publicUrl`) |
| Messages/posts/notifications | **Mixed** | DB insert failures generally surface; **notification insert skipped** returns `ok: true, skipped` server-side — recipient unaware |
| Expenses/payouts | **Mixed** | Create/update returns `error` string (`createPropFirmExpense`); **load** drops unmappable rows (C8) |

### 3.2 Incorrect data displayed as correct

| Scenario | Verdict | Evidence |
|----------|---------|----------|
| Dashboard vs Trades stats | **Confirmed risk** | Same `appDataCache` but different completeness flags (`isTradesHistoryComplete`, `isAnalyticsHistoryComplete`) |
| Stale Web cache | **Confirmed** | `INITIAL_TRADES_LIMIT = 120` (`appDataCache.ts`); dashboard may render before full history |
| Stale iOS GRDB | **Potential** | Analytics GRDB flags ON in iOS production shipped set |
| Pagination limits | **Confirmed** | Psychology cap + dashboard window; journal RPC fallback (C7) |
| Wrong P&L / win rate | **Confirmed paths** | Broker `tradesWithoutPnL` counter in persist; merge C6; analytics aggregates lag journal |
| Tax export excludes records | **Confirmed by filter** | `buildPropFirmTaxCsv` filters `inPeriod` — no row-level warning for excluded data |

### 3.3 Background failures

| Scenario | User visibility | Evidence |
|----------|-----------------|----------|
| Broker auto-sync stops | Settings heartbeat / manual sync | `docs/tradovate/BROKER_SYNC_WORKER.md`, `tradovateListenerStatus.ts` |
| Expired OAuth | `reconnect_required` on connection row | `syncTradovateBrokerAccount.ts` L1176–1187 |
| Crons | No user notice | `app/api/cron/weekly-trading-reports/route.ts` |
| Realtime disconnect | **Potential** stale UI | `lib/communityRoomUnread.ts` sets `needsReconcile` on `CHANNEL_ERROR` — reconcile may be missed on some surfaces |
| Push failures | None to recipient | `dmNotify.ts` `pushed: 0`; APNs token cleanup for permanent errors only (`apns.ts`) |

### 3.4 Swallowed errors (sample inventory)

| Pattern | Location | Effect |
|---------|----------|--------|
| `.catch(() => {})` | `lib/appDataCache.ts` L363, L369 (streaks/reports import) | Secondary invalidation fails quietly |
| `.catch(() => null)` | `lib/dataPrefetch.ts`, `InputTradeForm.tsx`, affiliate/referrals pages | Empty/null substitute |
| `.catch(() => [])` | `dataPrefetch.ts`, `userStreaksCache.ts`, `backtest/page.tsx` | Empty trades/accounts |
| RPC error → null | `tradeOwnerRead.ts` | Hidden read failures |
| Referral backfill | `ensureProfileForUser.ts` L58, L65–68 — no prod log | Lost referral only |
| `void write().catch(() => {})` | `lib/nativeSilentCacheBridge.ts` | Native disk cache may lag |
| JSON parse `.catch(() => null)` | Multiple API routes | Bad body → null, then 400 or skip |

**Not found (this pass):** Widespread empty `catch {}` blocks in product logic; most trade saves **await DB** before success haptics (`saveManualTrade.ts`).

### 3.5 Data corruption scenarios

| Scenario | Likelihood | Mitigation in repo |
|----------|------------|-------------------|
| Duplicate broker trades | Low | `broker_lifecycle_id` unique index, fill identity index |
| Concurrent edit overwrite | Medium | Last writer wins; no version column in client audit |
| Partial financial transaction | Medium | Payout delete restore migration (`20261024043000_delete_prop_payout_restore_balance.sql`) — **repair for one path** |
| Wrong account association | Low–medium | RLS + user_id on writes; broker mapping checks in sync |
| Cache invalidation miss | **Confirmed** | Feed bootstrap; analytics revision on Web |
| Web/iOS race | **Potential** | Independent caches + GRDB |

### 3.6 User trust — “success” when failed

| Flow | Misleading success? | Evidence |
|------|---------------------|----------|
| Manual trade + public post | **Partial** — trade saved, post fails → `ok: false, code: "post"` (user may not distinguish) | `saveManualTrade.ts` |
| Broker sync | **Yes possible** — `tradesCreated` < `completed.length` without thrown error | C1 + sync summary still completes |
| Stripe checkout | **Potential** — webhook 200 but profile not updated | C5, C6; client reconciliation poll mitigates partially |
| Notification sent | **Yes** — server `ok: true` when skipped/deduped | Notification handlers |
| Expense saved | **Usually accurate** — explicit error on insert failure | `createPropFirmExpense` |
| iOS global upload queue | **Better** — coordinator pattern | `GlobalUploadCoordinator` (native) vs Web partial outbox weakness (**Potential** from prior audits) |

---

## 4. Per-item detail (top 10 confirmed)

### 4.1 C1 — Broker persist loop continues on error

- **Files:** `lib/integrations/tradovate/persistBrokerTrades.ts` (insert L277–283, update L250–259).  
- **How:** For each reconstructed lifecycle, failed `insert`/`update` does not throw; sync wrapper only throws on **thrown** exceptions (`syncTradovateBrokerAccount.ts` L981–993), not on partial counts.  
- **User notice:** Sync UI may show success / partial depending on `deriveTradovateClientSyncResult` and `import_partial`.  
- **Impact:** **Journal holes** — executions may be updated while trade row missing (execution update L261–272 still runs after failed update).  
- **Detection:** Tradovate structured logs (`logTradovateSyncSummary` — inserted vs `completedLifecycles`).  
- **Recovery:** Manual re-sync; no automatic repair loop in client.

### 4.2 C2/C3 — Owner RPC read masking

- **Files:** `lib/tradeOwnerRead.ts`.  
- **How:** Transient RPC/RLS errors indistinguishable from “no trade”.  
- **Impact:** Features using `rpcTradeOwnerRead` without separate error check show empty state.

### 4.3 C4 — Prefetch swallow

- **Files:** `lib/dataPrefetch.ts`, consumed from `UserProfileProvider.tsx`.  
- **How:** Failed warm leaves **empty cache**; user lands on dashboard with zero trades until another loader runs.  
- **Notice:** Often **none** (empty state UX).

### 4.4 C6 — Stripe webhook 200

- **Files:** `app/api/stripe/webhook/route.ts`.  
- **How:** Stripe stops retrying on 200; inner `console.error` only.  
- **Impact:** **Paid user without `is_pro`** until client reconciliation or support.  
- **Detection:** Stripe dashboard vs Supabase profile; optional Sentry if error logged.

### 4.5 C7 — Psychology fallback

- **Files:** `lib/psychology/reports/journalTrades.ts`.  
- **How:** If RPC returns empty array without error, uses **dashboard-capped** trades (missing journal fields).  
- **Impact:** AI/report quality degraded **silently**.

### 4.6 C8 — Expense row mapping

- **Files:** `lib/propFirmExpenses.ts` `mapExpenseRow`, `loadPropFirmExpenses`.  
- **How:** Legacy/invalid `expense_type` or `tracker_kind` → row omitted from UI and **tax CSV input list**.  
- **Impact:** **Financial export gap** if DB has bad rows from old migrations.

### 4.7 Cache merge (C6 in ranked list)

- **Files:** `lib/appDataCache.ts` `mergeTradesInCache`, `upsertTradeInCache`, `applyBrokerImportedTradeToCache` (patch queue **mitigates** broker race).  
- **How:** Partial object over full row.  
- **Notice:** Subtle wrong fields until hard refresh / invalidation.

### 4.8 Analytics vs journal (rank 5)

- **Files:** `supabase/migrations/20260921120000_trade_daily_stats_analytical_foundation.sql`, dashboard V3 RPCs; Web lacks default `analyticsRevisionRepair` (iOS has flag).  
- **Status:** **Potential** desync until revision refetch.

### 4.9 Partial broker import (rank 7)

- **Files:** `lib/integrations/tradovate/tradovateSyncCompleteness.ts`, `syncTradovateBrokerAccount.ts` L1025–1080.  
- **How:** `IMPORT_SUCCESS_PARTIAL` still releases lock with `partial` status.  
- **Notice:** Depends on client handling `import_partial` / error codes.

### 4.10 Notification “success” without delivery (rank 20)

- **Files:** `lib/server/notifications/handlers/dmNotify.ts`, `commentNotify.ts`, etc.  
- **How:** Preferences/block → `{ ok: true, skipped: ... }`.  
- **Impact:** Social trust, not journal integrity.

---

## 5. Existing detection & recovery mechanisms

| Mechanism | What it catches | Gap |
|-----------|-----------------|-----|
| Tradovate sync logs + summary fields | Partial persist counts | Not user-facing alerts |
| `last_sync_status` / `reconnect_required` on broker rows | Token death | User must open integrations |
| Worker heartbeat | Auto-sync down | Settings UI |
| `analytics_bump_user_revision` + iOS repair flags | Stale charts | Web often OFF |
| Broker patch queue in `appDataCache` | Race during import | Does not fix C1 DB skip |
| Unique indexes on executions / lifecycle | Duplicate fills | Trade row still missing if insert skipped |
| Stripe client reconciliation poll | Post-checkout | Does not fix all webhook paths |
| Sentry (optional, ~10% traces) | Some server errors | Not comprehensive |
| GlobalUploadCoordinator (iOS) | Upload retry / queue | Web less unified |
| Payout delete restore trigger | Balance after delete | Narrow scope |

**No in-repo founder paging** for silent failures (per observability audit).

---

## 6. Top 10 recommended safeguards (lightweight)

1. **Broker persist:** After loop, if `tradesCreated + tradesUpdated < expected`, throw or return **`trade_upsert_failed`** with user-visible partial summary (build on existing `logTradovateSyncSummary`).  
2. **`tradeOwnerRead.ts`:** Return `{ row, error }` discriminated union; never conflate error with missing.  
3. **Prefetch:** On warm failure, set cache **`invalidated`** + Sentry breadcrumb; avoid `.catch(() => [])` without metric.  
4. **Stripe webhook:** Return **5xx** on profile mirror failure for retryable events; idempotent handlers only.  
5. **Analytics:** Enable revision repair on Web or invalidate dashboard bootstrap on trade mutation success.  
6. **Expense load:** If `mapExpenseRow` drops rows, surface **“N records could not be loaded”** once.  
7. **Psychology journal:** Do not fallback to capped rows when RPC returns empty — treat as error.  
8. **Contract test:** Assert `persistBrokerTrades` fails loud when insert error injected (unit test).  
9. **Sync UI:** Always show when `completedLifecycles > tradesInserted + tradesUpdated`.  
10. **Observability:** One dashboard query — daily count of syncs where `tradesInserted + tradesUpdated < completedLifecycles` (log-based metric).

---

## 7. Priority before scaling

1. Fix **C1 broker persist continue** (highest financial trust).  
2. Fix **read-path error masking** (C2/C3).  
3. **Stripe webhook retry semantics** (C5/C6).  
4. Align **analytics revision** visibility Web/iOS.  
5. Remove **silent prefetch empty states** (C4).  
6. Audit **notification `ok: true, skipped`** for user-facing delivery receipts (optional product decision).

---

## Appendix — File index

| Area | Paths |
|------|--------|
| Broker persist | `lib/integrations/tradovate/persistBrokerTrades.ts`, `syncTradovateBrokerAccount.ts` |
| Owner reads | `lib/tradeOwnerRead.ts` |
| Web cache | `lib/appDataCache.ts`, `lib/dataPrefetch.ts` |
| Manual save | `lib/saveManualTrade.ts` |
| Reels / media | `lib/reels.ts` |
| Billing | `app/api/stripe/webhook/route.ts` |
| Expenses / tax CSV | `lib/propFirmExpenses.ts`, `lib/propFirmExpenseTaxExport.ts` |
| Psychology | `lib/psychology/reports/journalTrades.ts` |
| Notifications | `lib/server/notifications/NotificationService.ts`, `lib/server/push/apns.ts` |
| Realtime | `lib/communityRoomUnread.ts`, `app/(app)/feed/page.tsx` |
| iOS uploads | `native-ios/.../GlobalUploadCoordinator.swift` |
| Profile signup | `lib/ensureProfileForUser.ts` |

---

*End of report.*
