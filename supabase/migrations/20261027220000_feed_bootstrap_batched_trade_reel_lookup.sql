-- Feed items: batch newest trade-attached reel per page (replaces per-post lateral).
-- Staging benchmark: supabase/staging/benchmark/run-feed-trade-reel-lookup-benchmark.mjs

create index if not exists reels_trade_id_created_at_id_idx
  on public.reels (trade_id, created_at desc, id desc)
  where trade_id is not null;

comment on index public.reels_trade_id_created_at_id_idx is
  'Feed items: newest reel per trade_id for batched page hydration.';

do $mig$
declare
  src text;
  updated text;
  v_items_pos int;
  v_batch_ctes text;
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

  if position('post_page_trade_keys' in src) > 0
     and position('page_latest_trade_reels' in src) > 0 then
    return;
  end if;

  if position('left join lateral' in src) = 0
     or position('where r.trade_id = coalesce(p.trade_id, p.id)' in src) = 0 then
    raise exception 'rpc_v1_feed_bootstrap trade-reel lateral anchor not found';
  end if;

  updated := src;

  updated := replace(
    updated,
    $old_lat_blank$
      left join public.posts p on pg.kind = 'post' and p.id = pg.id
      
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
$old_lat_blank$,
    $new_lat$
      left join public.posts p on pg.kind = 'post' and p.id = pg.id
      left join post_page_trade_keys ptk on ptk.post_id = p.id
      left join page_latest_trade_reels tr on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key
$new_lat$
  );

  if updated = src then
    updated := replace(
      updated,
      $old_lat$
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
$old_lat$,
$new_lat2$
      left join post_page_trade_keys ptk on ptk.post_id = p.id
      left join page_latest_trade_reels tr on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key
$new_lat2$
    );
  end if;

  if updated = src then
    updated := replace(
      updated,
      $old_lat_ind$
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
$old_lat_ind$,
$new_lat3$
      left join post_page_trade_keys ptk on ptk.post_id = p.id
      left join page_latest_trade_reels tr on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key
$new_lat3$
    );
  end if;

  if updated = src then
    raise exception 'rpc_v1_feed_bootstrap trade-reel lateral replace failed';
  end if;

  v_items_pos := position('  items as (' in updated);
  if v_items_pos = 0 then
    raise exception 'rpc_v1_feed_bootstrap items CTE anchor not found';
  end if;

  v_batch_ctes := $batch$
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
$batch$;

  updated := substring(updated from 1 for v_items_pos - 1)
    || v_batch_ctes
    || substring(updated from v_items_pos);

  if position('post_page_trade_keys' in updated) = 0 then
    raise exception 'rpc_v1_feed_bootstrap batch CTE insert failed';
  end if;

  if position('security definer' in lower(updated)) > 0 then
    raise exception 'rpc_v1_feed_bootstrap must stay security invoker';
  end if;

  execute updated;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_feed_bootstrap'
      and pg_get_function_identity_arguments(p.oid) =
        'p_scope text, p_content_filter text, p_limit integer, p_cursor text'
      and p.prosecdef
  ) then
    raise exception 'rpc_v1_feed_bootstrap must remain security invoker after patch';
  end if;
end
$mig$;

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — batched trade-reel hydration on post pages; Following cand per-followee lateral.';
