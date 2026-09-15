-- Embed linked trade public description on profile reels tab (single round-trip for clip titles).

create or replace function public.rpc_v1_profile_tab_reels(
  p_profile_id uuid,
  p_limit integer default 24,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 100);
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_can_view boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_next_cursor text := null;
begin
  if p_profile_id is null then
    raise exception 'invalid_profile_id' using errcode = '22023';
  end if;

  select (
    v_viewer = p_profile_id
    or coalesce(p.is_private, false) = false
    or exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = p_profile_id
    )
  ) into v_can_view
  from public.profiles p where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1', 'found', false),
      'data', jsonb_build_object('tab', 'reels', 'items', '[]'::jsonb, 'engagement', '{}'::jsonb, 'next_cursor', null)
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select r.*
    from public.reels r
    where r.user_id = p_profile_id
      and (
        v_cursor_ts is null
        or (r.created_at, r.id) < (v_cursor_ts, v_cursor_id)
      )
    order by r.created_at desc, r.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  ),
  enriched as (
    select
      tr.*,
      t.id as linked_trade_id,
      t.public_description as linked_trade_public_description,
      t.is_public as linked_trade_is_public,
      t.ticker as linked_trade_ticker,
      t.direction as linked_trade_direction,
      t.pnl as linked_trade_pnl,
      t.rr as linked_trade_rr
    from trimmed tr
    left join public.trades t on t.id = tr.trade_id
  )
  select
    coalesce(
      jsonb_agg(
        to_jsonb(e) - array[
          'linked_trade_id',
          'linked_trade_public_description',
          'linked_trade_is_public',
          'linked_trade_ticker',
          'linked_trade_direction',
          'linked_trade_pnl',
          'linked_trade_rr'
        ] || case
          when e.linked_trade_id is not null then jsonb_build_object(
            'trades', jsonb_build_object(
              'id', e.linked_trade_id,
              'public_description', e.linked_trade_public_description,
              'is_public', e.linked_trade_is_public,
              'ticker', e.linked_trade_ticker,
              'direction', e.linked_trade_direction,
              'pnl', e.linked_trade_pnl,
              'rr', e.linked_trade_rr
            )
          )
          else '{}'::jsonb
        end
        order by e.created_at desc, e.id desc
      ),
      '[]'::jsonb
    ),
    (
      select case when (select count(*) from page) > v_limit then
        (to_char(last_row.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || last_row.id::text)
      else null end
      from (
        select created_at, id from trimmed
        order by created_at asc, id asc
        limit 1
      ) last_row
    )
  into v_items, v_next_cursor
  from enriched e;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'reels',
      'items', v_items,
      'engagement', '{}'::jsonb,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;
