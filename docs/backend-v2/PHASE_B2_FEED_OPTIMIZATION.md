# Phase B2 — Feed RPC & Loading Optimization

Web performance program **Phase B2** only. Messages, Trade Rooms, bundle, and full Realtime consolidation are **not** started here.

## Status

| Item | State |
|------|--------|
| Optimization migration | `supabase/migrations/20260820224542_rpc_v1_feed_bootstrap_optimize.sql` |
| Rollback SQL | `supabase/migrations/rollback/20260820224542_rpc_v1_feed_bootstrap_rollback.sql` |
| Applied to production | **No** — local/staging review first |
| Contract fixtures/tests | `lib/backendV2/feedContractFixtures.ts`, `feedContractSchema.ts`, `feedBootstrapContract.test.ts` |
| Benchmark script | `scripts/benchmark-feed-rpc.mjs` |
| HAR 7 baseline | `rpc_v1_feed_bootstrap` ~1.40s, ~3.98KB payload, single request |
| native-ios/ touched | **No** |
| Session/Dashboard/Auth/FreePlan touched | **No** |

---

## B1 — Frozen Feed contract (pre-optimization)

### Deployed function metadata

| Property | Value |
|----------|--------|
| Name | `rpc_v1_feed_bootstrap` |
| Args | `p_scope text` (default `'following'`), `p_content_filter text` (default `'all'`), `p_limit integer` (default `8`, max `40`), `p_cursor timestamptz` (default `null`) |
| Returns | `jsonb` |
| Volatility | `STABLE` |
| Security | `SECURITY INVOKER` |
| search_path | `public` |
| Grants | `REVOKE ALL FROM public`; `GRANT EXECUTE TO authenticated` |

### Top-level JSON keys

**meta:** `contract_version` (`"v1"`), `server_time` (ISO UTC), `viewer_id`

**data:** `scope`, `content_filter`, `items`, `authors`, `engagement`, `stories`, `story_authors`, `next_cursor`, `page_meta`, `following_ids_echo`

### Content item discriminators (`items[].kind`)

| kind | Source table | Filter mapping |
|------|--------------|----------------|
| `post` | `posts` | `trades`, `all` |
| `profile_post` | `profile_posts` | `posts`, `all` |
| `achievement_post` | `achievement_posts` + `achievements` | `achievements`, `all` |
| `reel` | `reels` | `reels`, `all` (non-trade-linked when `all`) |

### Pagination (before B2)

- Branch-local `LIMIT v_limit+1`, merged by `created_at DESC, id DESC`
- `next_cursor`: last item timestamp only (skip/duplicate risk on equal timestamps across kinds)
- Initial page size: **8** (`FEED_PAGE_SIZE` in `lib/feedContent.ts`)

### Scope semantics

- **Following:** authors in `followers` list; excludes viewer's own content; stories (24h) included
- **Global:** authors **not** in following set (or all if no follows); empty stories
- **Empty Following:** early return with `items: []`, `following_ids_echo: []`

### Engagement

Set-based via `feed_engagement_counts(post_ids, profile_ids, achievement_ids, reel_ids)` — not per-item correlated counts.

---

## B2 — Current vs optimized architecture

### Before (Phase 4 RPC)

```
auth.uid() → followers[] once
→ 4 UNION ALL branches (each LIMIT n+1) — all branches planned even when filter excludes them
→ merge ORDER BY created_at, id only
→ hydrate items with 4 separate profiles joins
→ feed_engagement_counts (set-based)
→ stories + story_authors
```

### After (Phase B2)

```
auth.uid() once
→ followers[] once
→ boolean gates skip excluded branches at plan time (trades/posts/achievements/reels)
→ branch-level keyset filter via _v1_feed_before_cursor (legacy timestamp OR composite)
→ merge ORDER BY created_at DESC, kind_rank DESC, id DESC (stabilizes equal timestamps)
→ single authors map → payload profile snippets (no 4× profiles join)
→ feed_engagement_counts (unchanged, set-based)
→ stories + story_authors (unchanged)
→ next_cursor: ISO|kind|uuid
```

### Root cost breakdown (estimated)

| Cost driver | Before | After |
|-------------|--------|-------|
| All 4 content scans on single-filter | Always union 4 | Skip dead branches |
| profile_posts feed scan | No `(user_id, created_at)` index | **New index** |
| Profile hydration | 4 LEFT JOIN profiles | 1 authors agg + jsonb lookup |
| Pagination correctness | Timestamp-only cursor | Composite keyset cursor |
| Engagement | Set-based (good) | Unchanged |
| RLS | Per-table policies (unchanged) | Unchanged — no policy edits |

---

## Query shape changes

### New helpers (private)

- `_v1_feed_kind_rank(text)` — deterministic kind ordering for ties
- `_v1_feed_parse_cursor(text)` — legacy timestamp or `ISO\|kind\|uuid`
- `_v1_feed_before_cursor(...)` — keyset predicate shared by branches

### Index added

```sql
create index profile_posts_user_id_created_at_idx
  on public.profile_posts (user_id, created_at desc, id desc);
```

**Rationale:** `profile_posts` lacked a user-scoped created_at index used by Following/Global branches. Existing indexes on `posts`, `reels`, `achievement_posts`, `followers` were already present.

### Cursor format (B2)

| Field | Format |
|-------|--------|
| Initial page | `p_cursor = null`, `p_limit = 8` |
| next_cursor | `{ISO8601UTC}\|{kind}\|{uuid}` e.g. `2026-08-20T12:00:00.000Z\|post\|11111111-...` |
| Legacy input | Plain ISO timestamp still accepted (strict `<` on `created_at`) |

Client passes cursor opaquely via `feedV2CursorRef` — no client change required beyond accepting composite string.

### Ordering stabilization

When multiple items share `created_at`, old RPC used UUID order only (nondeterministic across kinds). B2 adds kind rank: `post > profile_post > achievement_post > reel`, then `id DESC`.

---

## RLS / security verification

- **No RLS policy changes** in B2 migration
- **SECURITY INVOKER** preserved — authorization remains table RLS
- Helper functions: `REVOKE ALL FROM public` — not callable by clients
- Blocked/private/deleted content: still enforced by existing RLS + achievement `is_public` filter
- Viewer own content: still excluded via `user_id is distinct from v_uid`

---

## Client Feed loading (verified, no B2 code changes required)

| Check | Status |
|-------|--------|
| One initial Feed RPC when `backendV2.feed` ON | Yes — `loadFeedBootstrapForUser` |
| Stale filter rejection | Yes — `feedRequestGenerationRef` |
| Pagination appends | Yes — `feedV2CursorRef` passed on load-more |
| Session restore | Yes — `readFeedSession` |
| No per-card Supabase on initial render | Yes — RPC hydrates all items |
| Likes/comments patch item | Yes — engagement maps + realtime handlers |
| Media lazy-loaded | Yes — card components |

---

## Realtime inventory (Feed mounted)

| Channel | Table/events | Behavior |
|---------|--------------|----------|
| `feed-trade-posts-{userId}` | `posts` INSERT | Fetch single row, patch state |
| `feed-profile-posts-{userId}` | `profile_posts` INSERT | Fetch single row, patch |
| `feed-achievement-posts-{userId}` | `achievement_posts` INSERT | Fetch single row, patch |
| `feed-reels-{userId}` | `reels` INSERT | Fetch single row, patch |
| `feed-reel-likes-{userId}` | reel likes | Incremental like patch |

All channels: gated by `contentType` + `mode`, generation-stamped to reject stale events, `removeChannel` on unmount. **No full Feed refetch** on INSERT. **No duplicate subscription fixes needed** in B2 — structure is already one channel per table.

Full cross-app Realtime consolidation deferred to dedicated phase.

---

## Database validation (local/staging)

### Apply optimization

```bash
supabase db push   # or migration up on staging
```

### Benchmark (30 warm runs)

```bash
SUPABASE_URL=... SUPABASE_ANON_KEY=... BENCHMARK_USER_JWT=... \
node scripts/benchmark-feed-rpc.mjs
```

**Targets:** warm median &lt;250ms, p95 &lt;500ms on representative data.

### Rollback test cycle

1. Apply `20260820224542_rpc_v1_feed_bootstrap_optimize.sql`
2. Run benchmark + contract compare
3. Apply `rollback/20260820224542_rpc_v1_feed_bootstrap_rollback.sql`
4. Verify timestamptz RPC restored
5. Re-apply optimization migration
6. Re-verify

---

## Contract comparison notes

| Area | Change |
|------|--------|
| Top-level keys | **None** |
| Item payload shapes | **None** |
| `next_cursor` format | **Extended** — composite when `has_more` (backward-compatible input) |
| Item order at equal timestamps | **Stabilized** — may differ from old UUID-only tie-break |

Validators: `validateFeedBootstrapContract`, `compareFeedBootstrapSemantics`.

---

## Files changed (Phase B2)

| Path | Purpose |
|------|---------|
| `supabase/migrations/20260820224542_rpc_v1_feed_bootstrap_optimize.sql` | Optimized RPC + index + helpers |
| `supabase/migrations/rollback/20260820224542_rpc_v1_feed_bootstrap_rollback.sql` | Executable rollback |
| `lib/backendV2/feedContractSchema.ts` | Contract validators |
| `lib/backendV2/feedContractFixtures.ts` | Scope/filter fixtures |
| `lib/backendV2/feedBootstrapContract.test.ts` | 26 contract tests |
| `scripts/benchmark-feed-rpc.mjs` | Staging benchmark |
| `docs/backend-v2/PHASE_B2_FEED_OPTIMIZATION.md` | This document |
| `package.json` | Added feed contract test to `test:backend-v2` |

---

## Tests / build

```bash
npm run test:backend-v2   # 110 tests pass
npm run lint
npm run build
```

---

## Remaining Feed bottlenecks

1. **Production DB latency** — HAR 7 ~1.40s likely includes pool/cold planner; benchmark after migration apply required
2. **Trade-linked reel lateral** — one LATERAL per trade post on page (bounded by page size 8)
3. **RLS per-row evaluation** — unchanged; future phase may optimize `(select auth.uid())` patterns table-wide
4. **Realtime** — 5 channels while mounted; consolidation phase pending
5. **Dual-run REST compare** — still available in dev for regression detection

---

## Confirmations

- **Production:** migration **not** applied automatically
- **Untouched:** auth, Session RPC, Dashboard RPC, FreePlan, `native-ios/`
- **Stopped after B2** — Messages/bundle/full Realtime not started
