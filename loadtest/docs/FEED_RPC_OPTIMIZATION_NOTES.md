# Feed RPC first-page — optimization notes (no production changes)

Review target: `public.rpc_v1_feed_bootstrap` through `20261005140000_feed_bootstrap_safe_trade_reads.sql`.

**Implemented (production):** `20261027120000_feed_bootstrap_block_peers_once.sql` — one `get_active_block_peer_ids()` per RPC + `user_blocks(blocker_id)` index.

**In progress (staging-only prototype):** Following first-page `cand` per-followee lateral top-N — see `supabase/staging/docs/FEED_FOLLOWING_CAND_OPTIMIZATION.md` and `supabase/staging/verify/feed_following_cand_explain_analyze.sql`.

**Do not apply new cand SQL to production without staging EXPLAIN ANALYZE + equivalence on hxlcvffvyadlxcsqxxoy.**

## First page vs cursor page

| Path | SQL behavior |
|------|----------------|
| **First page** (`p_cursor` null) | Four branches (posts, profile_posts, achievement_posts, reels) each scan **recent** rows with `users_have_active_block` per candidate row, union, window sort, hydrate, `feed_engagement_counts`. |
| **Cursor page** | Same branches with `_v1_feed_before_cursor` — **bounded** to rows older than cursor — typically cheaper (matches load-test `feed_page` faster than `feed`). |

## Behavior-preserving opportunities (hypotheses)

1. **Block list once per RPC** — `get_active_block_peer_ids()` already exists; replacing per-row `users_have_active_block(v_uid, author_id)` with `NOT (author_id = ANY(block_peers))` should preserve bidirectional block semantics if the array matches the function. **Verify** on staging with block fixtures.

2. **Following scope for users with follows** — Web/iOS often load **following** first page, not global. Global branch uses `not (user_id = any (v_following))` when the viewer follows anyone — different plan shape than `user_id = any (v_following)`. Load tests should use `client_realistic` + `following` scope for representative mix; `supabase_direct` may keep global for stress.

3. **RLS + SECURITY INVOKER** — Required for privacy; optimizations must stay invoker-safe or use approved definer helpers (pattern already used for trade payload).

4. **Hydration** — Items CTE joins trades/reels per page row; limit is capped at 40 (`p_limit` clamp). No change suggested without profiling.

5. **Indexes (existing)** — `posts (created_at desc)`, `posts (user_id, created_at desc)`, analogous indexes on other content tables (`20260804230000_phase3_hot_path_indexes.sql`, `20260820224542_rpc_v1_feed_bootstrap_optimize.sql`). Missing or unused indexes should show up in **EXPLAIN (without ANALYZE)** on staging clone.

## Evidence required before any migration

- Staging `EXPLAIN` first page vs cursor for both `following` and `global` scopes.
- Row counts on content tables (see `loadtest/diagnostics/production-feed-readonly.sql` section 4).
- p95 comparison on **supabase_direct** vs **client_realistic** workloads with ≥1 test user per 5 VUs.
