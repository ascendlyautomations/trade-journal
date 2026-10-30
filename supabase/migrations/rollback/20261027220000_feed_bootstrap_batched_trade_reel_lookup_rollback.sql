-- Rollback: restore per-post trade-reel lateral; drop batched lookup index.

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_feed_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_scope text, p_content_filter text, p_limit integer, p_cursor text';

  if src is null then
    raise exception 'rpc_v1_feed_bootstrap was not found';
  end if;

  if position('post_page_trade_keys' in src) = 0 then
    return;
  end if;

  updated := src;

  updated := replace(
    updated,
    $batched_join$
      left join post_page_trade_keys ptk on ptk.post_id = p.id
      left join page_latest_trade_reels tr on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key
$batched_join$,
    $lateral_join$
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
$lateral_join$
  );

  updated := replace(
    updated,
    $batch_ctes$
  post_page_trade_keys as (
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
  ),
  items as (
$batch_ctes$,
    $items$
  items as (
$items$
  );

  if updated = src then
    raise exception 'rpc_v1_feed_bootstrap batched trade-reel rollback failed';
  end if;

  execute updated;
end
$mig$;

drop index if exists public.reels_trade_id_created_at_id_idx;

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — Following cand uses per-followee lateral top-N; blocks via get_active_block_peer_ids.';
