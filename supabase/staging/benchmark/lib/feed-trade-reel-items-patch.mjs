/**
 * Patch rpc_v1_feed_bootstrap body (post buildProductionShapedBody) for trade-reel lookup variants.
 */

const LATERAL_JOIN = `      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'`

const BATCH_CTes = `  post_page_trade_keys as (
    select pg.id as post_id, coalesce(p.trade_id, p.id) as trade_key
    from page pg
    inner join public.posts p on pg.kind = 'post' and p.id = pg.id
  ),
  page_latest_trade_reels as (
    select distinct on (r.trade_id) r.*
    from public.reels r
    where exists (select 1 from page where kind = 'post')
      and r.trade_id in (select trade_key from post_page_trade_keys)
    order by r.trade_id, r.created_at desc, r.id desc
  ),`

const BATCH_JOINS = `      left join post_page_trade_keys ptk on ptk.post_id = p.id
      left join page_latest_trade_reels tr on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key`

export const COMPOSITE_INDEX_SQL = `
create index if not exists reels_trade_id_created_at_id_idx
  on public.reels (trade_id, created_at desc, id desc)
  where trade_id is not null;
`

export const DROP_COMPOSITE_INDEX_SQL = `
drop index if exists public.reels_trade_id_created_at_id_idx;
`

/** Production-shaped lateral (no post-only p.id guard). */
export function applyBaselineTradeReelLookup(body) {
  if (!body.includes(LATERAL_JOIN)) {
    throw new Error("feed bootstrap body missing expected trade-reel lateral block")
  }
  return body
}

/** Page-scoped DISTINCT ON batch + post-only join guards. */
export function applyBatchedTradeReelLookup(body) {
  if (!body.includes(LATERAL_JOIN)) {
    throw new Error("feed bootstrap body missing expected trade-reel lateral block")
  }
  let next = body.replace(LATERAL_JOIN, BATCH_JOINS)
  const anchor = `  authors as (`
  const idx = next.indexOf(anchor)
  if (idx < 0) throw new Error("feed bootstrap body missing authors CTE")
  const itemsIdx = next.indexOf("  items as (", idx)
  if (itemsIdx < 0) throw new Error("feed bootstrap body missing items CTE")
  next = `${next.slice(0, itemsIdx)}${BATCH_CTes}\n${next.slice(itemsIdx)}`
  return next
}
