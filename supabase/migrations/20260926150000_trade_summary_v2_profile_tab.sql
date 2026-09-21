-- Phase 8B — canonical TradeSummary wire + Profile tab trades V2 (V1 unchanged for rollback).

-- ---------------------------------------------------------------------------
-- Viewer-aware card note preview (ProfileTradeCard uses notePreview, not full notes).
-- Owner: first 360 chars of private notes (matches native TradeMapper).
-- Non-owner: public_description only — do not leak private notes on summary wire.
-- ---------------------------------------------------------------------------

create or replace function public.trade_summary_note_preview(
  p_trade public.trades,
  p_viewer_id uuid
)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when p_viewer_id is not null and p_viewer_id = p_trade.user_id then
      nullif(left(trim(coalesce(p_trade.notes, '')), 360), '')
    else
      nullif(left(trim(coalesce(p_trade.public_description, '')), 360), '')
  end;
$$;

comment on function public.trade_summary_note_preview(public.trades, uuid) is
  'Phase 8B: Profile card note line — owner notes preview vs public caption for other viewers.';

-- ---------------------------------------------------------------------------
-- Canonical TradeSummary JSON (list/card transport). Viewer-aware note_preview only.
-- Does not include psychology, import/broker metadata, account identifiers, or full notes.
-- ---------------------------------------------------------------------------

create or replace function public.trade_summary_json(
  p_trade public.trades,
  p_viewer_id uuid default null
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(
    jsonb_build_object(
      'summary_schema', 'trade_summary_v1',
      'id', p_trade.id,
      'user_id', p_trade.user_id,
      'ticker', p_trade.ticker,
      'direction', p_trade.direction,
      'pnl', p_trade.pnl,
      'rr', p_trade.rr,
      'points', p_trade.points,
      'contracts', p_trade.contracts,
      'entry_time', public.analytics_wire_trade_timestamp_utc(p_trade.entry_time),
      'exit_time', public.analytics_wire_trade_timestamp_utc(p_trade.exit_time),
      'created_at', to_char(
        p_trade.created_at at time zone 'utc',
        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
      ),
      'is_public', coalesce(p_trade.is_public, false),
      'public_description', p_trade.public_description,
      'note_preview', public.trade_summary_note_preview(p_trade, p_viewer_id),
      'image_url', p_trade.image_url,
      'image_crop', p_trade.image_crop,
      'image_display_mode', p_trade.image_display_mode,
      'mode', p_trade.mode,
      'account_type', p_trade.account_type,
      'trade_mode', p_trade.trade_mode,
      'duration_seconds', p_trade.duration_seconds,
      'duration_text', p_trade.duration_text
    )
  );
$$;

comment on function public.trade_summary_json(public.trades, uuid) is
  'Phase 8B canonical TradeSummary wire object for list/card surfaces.';

-- Owner-only extension (future journal/list migrations — not used by public profile tab).
create or replace function public.trade_summary_owner_extension_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_strip_nulls(
    jsonb_build_object(
      'account_id', nullif(trim(coalesce(p_trade.account_id, '')), '')
    )
  );
$$;

comment on function public.trade_summary_owner_extension_json(public.trades) is
  'Phase 8B owner-only summary fields — never merge into public/follower profile payloads.';

-- ---------------------------------------------------------------------------
-- Profile tab trades V2 — same gate, pagination, engagement as V1; TradeSummary items.
-- ---------------------------------------------------------------------------

create or replace function public.rpc_v1_profile_tab_trades_v2(
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
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_engagement jsonb := '{}'::jsonb;
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
  from public.profiles p
  where p.id = p_profile_id;

  if not coalesce(v_can_view, false) then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v2',
        'found', false,
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_viewer
      ),
      'data', jsonb_build_object(
        'tab', 'trades',
        'items', '[]'::jsonb,
        'engagement', '{}'::jsonb,
        'next_cursor', null
      )
    );
  end if;

  if p_cursor is not null and trim(p_cursor) <> '' then
    v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
    v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
  end if;

  with page as (
    select t.*
    from public.trades t
    where t.user_id = p_profile_id
      and t.is_public is true
      and (
        v_cursor_ts is null
        or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
      )
    order by t.created_at desc, t.id desc
    limit v_limit + 1
  ),
  trimmed as (
    select * from page limit v_limit
  )
  select
    coalesce(
      jsonb_agg(
        public.trade_summary_json(tr, v_viewer)
        order by tr.created_at desc, tr.id desc
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from page)
  into v_items, v_has_more
  from trimmed tr;

  if v_has_more then
    -- CTE `trimmed` is statement-scoped; derive cursor from returned summary items.
    select (elem->>'created_at') || '|' || (elem->>'id')
    into v_next_cursor
    from (
      select elem
      from jsonb_array_elements(v_items) as elem
      order by (elem->>'created_at') asc, (elem->>'id') asc
      limit 1
    ) sub;
  end if;

  with trade_ids as (
    select (elem->>'id')::uuid as id
    from jsonb_array_elements(v_items) elem
    where elem ? 'id'
  )
  select coalesce(jsonb_object_agg(
    ti.id::text,
    jsonb_build_object(
      'like_count', coalesce(lc.like_count, 0),
      'liked_by_me', coalesce(lc.liked_by_me, false),
      'comment_count', coalesce(cc.comment_count, 0)
    )
  ), '{}'::jsonb)
  into v_engagement
  from trade_ids ti
  left join lateral (
    select count(*)::integer as like_count,
      bool_or(v_viewer is not null and tl.user_id = v_viewer) as liked_by_me
    from public.trade_likes tl where tl.trade_id = ti.id
  ) lc on true
  left join lateral (
    select count(*)::integer as comment_count
    from public.trade_comments tc where tc.trade_id = ti.id
  ) cc on true;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v2',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'tab', 'trades',
      'items', v_items,
      'engagement', v_engagement,
      'next_cursor', v_next_cursor
    )
  );
end;
$$;

-- Shadow helper: compare V1 vs V2 profile tab payloads (card-relevant fields only).
create or replace function public.rpc_v1_profile_tab_trades_summary_shadow_compare(
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
  v_v1 jsonb;
  v_v2 jsonb;
  v_viewer uuid := auth.uid();
  v_is_owner boolean := false;
  v_v1_items jsonb;
  v_v2_items jsonb;
  v_diffs jsonb := '[]'::jsonb;
  v_i int;
  v_v1_row jsonb;
  v_v2_row jsonb;
  v_id text;
begin
  v_v1 := public.rpc_v1_profile_tab_trades(p_profile_id, p_limit, p_cursor);
  v_v2 := public.rpc_v1_profile_tab_trades_v2(p_profile_id, p_limit, p_cursor);

  v_is_owner := v_viewer is not null and v_viewer = p_profile_id;

  v_v1_items := coalesce(v_v1->'data'->'items', '[]'::jsonb);
  v_v2_items := coalesce(v_v2->'data'->'items', '[]'::jsonb);

  if jsonb_array_length(v_v1_items) <> jsonb_array_length(v_v2_items) then
    v_diffs := v_diffs || jsonb_build_array(jsonb_build_object(
      'kind', 'count_mismatch',
      'v1', jsonb_array_length(v_v1_items),
      'v2', jsonb_array_length(v_v2_items)
    ));
  end if;

  if (v_v1->'data'->>'next_cursor') is distinct from (v_v2->'data'->>'next_cursor') then
    v_diffs := v_diffs || jsonb_build_array(jsonb_build_object(
      'kind', 'cursor_mismatch',
      'v1', v_v1->'data'->'next_cursor',
      'v2', v_v2->'data'->'next_cursor'
    ));
  end if;

  if (v_v1->'meta'->>'found') is distinct from (v_v2->'meta'->>'found') then
    v_diffs := v_diffs || jsonb_build_array(jsonb_build_object(
      'kind', 'found_mismatch',
      'v1', v_v1->'meta'->'found',
      'v2', v_v2->'meta'->'found'
    ));
  end if;

  for v_i in 0 .. least(jsonb_array_length(v_v1_items), jsonb_array_length(v_v2_items)) - 1 loop
    v_v1_row := v_v1_items->v_i;
    v_v2_row := v_v2_items->v_i;
    v_id := v_v1_row->>'id';

    if v_v1_row->>'id' is distinct from v_v2_row->>'id' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object(
        'kind', 'id_order', 'index', v_i,
        'v1', v_v1_row->>'id', 'v2', v_v2_row->>'id'
      ));
    end if;

    if v_v1_row->>'ticker' is distinct from v_v2_row->>'ticker' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'ticker', 'id', v_id));
    end if;
    if v_v1_row->>'direction' is distinct from v_v2_row->>'direction' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'direction', 'id', v_id));
    end if;
    if v_v1_row->>'pnl' is distinct from v_v2_row->>'pnl' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'pnl', 'id', v_id));
    end if;
    if v_v1_row->>'rr' is distinct from v_v2_row->>'rr' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'rr', 'id', v_id));
    end if;
    if v_v1_row->>'points' is distinct from v_v2_row->>'points' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'points', 'id', v_id));
    end if;
    if v_v1_row->>'contracts' is distinct from v_v2_row->>'contracts' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'contracts', 'id', v_id));
    end if;
    if coalesce(v_v1_row->>'is_public', 'false') is distinct from coalesce(v_v2_row->>'is_public', 'false') then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'is_public', 'id', v_id));
    end if;
    if v_v1_row->>'image_url' is distinct from v_v2_row->>'image_url' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'image_url', 'id', v_id));
    end if;
    if v_v1_row->'image_crop' is distinct from v_v2_row->'image_crop' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'image_crop', 'id', v_id));
    end if;
    if v_v1_row->>'image_display_mode' is distinct from v_v2_row->>'image_display_mode' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'image_display_mode', 'id', v_id));
    end if;
    if v_v1_row->>'mode' is distinct from v_v2_row->>'mode' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'mode', 'id', v_id));
    end if;
    if v_v1_row->>'account_type' is distinct from v_v2_row->>'account_type' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'account_type', 'id', v_id));
    end if;
    if v_v1_row->>'trade_mode' is distinct from v_v2_row->>'trade_mode' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'trade_mode', 'id', v_id));
    end if;
    if v_v1_row->>'duration_seconds' is distinct from v_v2_row->>'duration_seconds' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'duration_seconds', 'id', v_id));
    end if;
    if v_v1_row->>'duration_text' is distinct from v_v2_row->>'duration_text' then
      v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'duration_text', 'id', v_id));
    end if;

    -- Note preview: owner compares notes prefix; non-owner compares public_description prefix.
    if v_is_owner then
      if nullif(left(trim(coalesce(v_v1_row->>'notes', '')), 360), '') is distinct from v_v2_row->>'note_preview' then
        v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'note_preview_owner', 'id', v_id));
      end if;
    else
      if nullif(left(trim(coalesce(v_v1_row->>'public_description', '')), 360), '') is distinct from v_v2_row->>'note_preview' then
        v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'note_preview_public', 'id', v_id));
      end if;
    end if;
  end loop;

  if (v_v1->'data'->'engagement') is distinct from (v_v2->'data'->'engagement') then
    v_diffs := v_diffs || jsonb_build_array(jsonb_build_object('kind', 'engagement_mismatch'));
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile_id', p_profile_id,
      'is_owner_viewer', v_is_owner,
      'trade_count', jsonb_array_length(v_v1_items),
      'v1_payload_bytes', octet_length(v_v1::text),
      'v2_payload_bytes', octet_length(v_v2::text),
      'reduction_pct', case
        when octet_length(v_v1::text) > 0 then
          round(100.0 * (1.0 - (octet_length(v_v2::text)::numeric / octet_length(v_v1::text)::numeric)), 2)
        else null
      end,
      'parity_ok', jsonb_array_length(v_diffs) = 0,
      'diffs', v_diffs,
      'removed_field_categories', jsonb_build_array(
        'full_notes',
        'psychology',
        'import_broker',
        'account_identifiers',
        'detail_only_columns'
      )
    )
  );
end;
$$;

revoke all on function public.trade_summary_note_preview(public.trades, uuid) from public;
grant execute on function public.trade_summary_note_preview(public.trades, uuid) to authenticated;

revoke all on function public.trade_summary_json(public.trades, uuid) from public;
grant execute on function public.trade_summary_json(public.trades, uuid) to authenticated;

revoke all on function public.trade_summary_owner_extension_json(public.trades) from public;
grant execute on function public.trade_summary_owner_extension_json(public.trades) to authenticated;

revoke all on function public.rpc_v1_profile_tab_trades_v2(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_trades_v2(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_trades_v2(uuid, integer, text) to anon;

revoke all on function public.rpc_v1_profile_tab_trades_summary_shadow_compare(uuid, integer, text) from public;
grant execute on function public.rpc_v1_profile_tab_trades_summary_shadow_compare(uuid, integer, text) to authenticated;
grant execute on function public.rpc_v1_profile_tab_trades_summary_shadow_compare(uuid, integer, text) to anon;
