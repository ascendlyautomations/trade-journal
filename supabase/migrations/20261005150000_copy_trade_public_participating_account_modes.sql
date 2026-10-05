-- Safe public aggregate: participating account ids + modes for one copy-trade action
-- (single feed post / one trades_public_read row — no sibling trade rows required).

create or replace function public.trade_summary_public_account_mode_for_owner_account(
  p_user_id uuid,
  p_account_id text
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.profile_statistics_resolve_account_mode(
    (
      select acc.mode
      from public.accounts acc
      where acc.id = public.analytics_trade_account_uuid(p_account_id)
        and acc.user_id is not distinct from p_user_id
      limit 1
    ),
    null,
    null
  );
$$;

comment on function public.trade_summary_public_account_mode_for_owner_account(uuid, text) is
  'Public copy-trade presentation — accounts.mode for one participating account (owner-scoped).';

revoke all on function public.trade_summary_public_account_mode_for_owner_account(uuid, text) from public;
grant execute on function public.trade_summary_public_account_mode_for_owner_account(uuid, text) to anon, authenticated;

create or replace function public.copy_trade_public_participating_account_modes_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with raw_ids as (
    select nullif(trim(coalesce(p_trade.source_account_id::text, '')), '') as account_id
    union
    select nullif(trim(coalesce(p_trade.account_id, '')), '')
    union
    select nullif(trim(v::text), '')
    from unnest(coalesce(p_trade.copied_account_ids, array[]::uuid[])) as v
  ),
  ids as (
    select distinct account_id
    from raw_ids
    where account_id is not null
  )
  select case
    when lower(trim(coalesce(p_trade.trade_mode, ''))) <> 'copy_traded' then '[]'::jsonb
    else coalesce(
      (
        select jsonb_agg(
          jsonb_strip_nulls(
            jsonb_build_object(
              'account_id', i.account_id,
              'account_mode', public.trade_summary_public_account_mode_for_owner_account(
                p_trade.user_id,
                i.account_id
              )
            )
          )
          order by i.account_id
        )
        from ids i
      ),
      '[]'::jsonb
    )
  end;
$$;

comment on function public.copy_trade_public_participating_account_modes_json(public.trades) is
  'Public copy-trade mode counts — one row per participating account (safe for feed/profile).';

revoke all on function public.copy_trade_public_participating_account_modes_json(public.trades) from public;
grant execute on function public.copy_trade_public_participating_account_modes_json(public.trades) to anon, authenticated;

create or replace function public.trade_summary_profile_copy_linkage_json(
  p_trade public.trades
)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when lower(trim(coalesce(p_trade.trade_mode, ''))) <> 'copy_traded' then '{}'::jsonb
    else jsonb_strip_nulls(
      jsonb_build_object(
        'account_id', nullif(trim(coalesce(p_trade.account_id, '')), ''),
        'source_account_id', nullif(trim(coalesce(p_trade.source_account_id::text, '')), ''),
        'copied_account_ids', case
          when p_trade.copied_account_ids is null or cardinality(p_trade.copied_account_ids) = 0 then null
          else to_jsonb(p_trade.copied_account_ids)
        end,
        'copy_trading_group_id', nullif(trim(coalesce(p_trade.copy_trading_group_id::text, '')), ''),
        'account_mode', public.trade_summary_profile_participating_account_mode(p_trade),
        'participating_account_modes', public.copy_trade_public_participating_account_modes_json(p_trade)
      )
    )
  end;
$$;

-- Feed payload: keep SECURITY DEFINER + block/visibility gates (20261005140000 feed_bootstrap_safe).
-- Extend guest/authed JSON with copy linkage + participating_account_modes only.

create or replace function public._v1_feed_post_trade_payload(
  p_trade_id uuid,
  p_reel public.reels,
  p_guest boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_trade public.trades%rowtype;
begin
  if p_trade_id is null then
    return null;
  end if;

  select * into v_trade
  from public.trades t
  where t.id = p_trade_id;

  if v_trade.id is null then
    return null;
  end if;

  if public.viewer_has_block_with(v_trade.user_id) then
    return null;
  end if;

  if not public.profile_is_visible_to_viewer(v_trade.user_id) then
    return null;
  end if;

  if coalesce(p_guest, false) then
    if coalesce(v_trade.is_public, false) = false then
      return null;
    end if;
    if not exists (
      select 1
      from public.profiles pr
      where pr.id = v_trade.user_id
        and coalesce(pr.is_private, false) = false
    ) then
      return null;
    end if;

    return jsonb_build_object(
      'created_at', v_trade.created_at,
      'public_description', v_trade.public_description,
      'user_id', v_trade.user_id,
      'account_id', v_trade.account_id,
      'source_account_id', v_trade.source_account_id,
      'copied_account_ids', v_trade.copied_account_ids,
      'copy_trading_group_id', v_trade.copy_trading_group_id,
      'participating_account_modes', public.copy_trade_public_participating_account_modes_json(v_trade),
      'ticker', v_trade.ticker,
      'direction', v_trade.direction,
      'account_type', v_trade.account_type,
      'mode', v_trade.mode,
      'trade_mode', v_trade.trade_mode,
      'points', v_trade.points,
      'entry_time', v_trade.entry_time,
      'exit_time', v_trade.exit_time,
      'entry_price', v_trade.entry_price,
      'exit_price', v_trade.exit_price,
      'trade_date', v_trade.trade_date,
      'duration_seconds', v_trade.duration_seconds,
      'duration_text', v_trade.duration_text,
      'image_url', v_trade.image_url,
      'image_crop', v_trade.image_crop,
      'is_public', true,
      'reels', case
        when p_reel.id is null or coalesce(p_reel.visibility, 'public') <> 'public' then null
        else jsonb_build_object(
          'id', p_reel.id,
          'user_id', p_reel.user_id,
          'video_url', p_reel.video_url,
          'thumbnail_url', p_reel.thumbnail_url,
          'duration_seconds', p_reel.duration_seconds,
          'trade_id', p_reel.trade_id,
          'visibility', p_reel.visibility
        )
      end
    );
  end if;

  if auth.uid() is distinct from v_trade.user_id
     and not (
       coalesce(v_trade.is_public, false)
       and public.profile_viewer_can_view_trades(v_trade.user_id)
     )
  then
    return null;
  end if;

  return jsonb_build_object(
    'created_at', v_trade.created_at,
    'public_description', v_trade.public_description,
    'user_id', v_trade.user_id,
    'account_id', v_trade.account_id,
    'source_account_id', v_trade.source_account_id,
    'ticker', v_trade.ticker,
    'direction', v_trade.direction,
    'account_type', v_trade.account_type,
    'mode', v_trade.mode,
    'trade_mode', v_trade.trade_mode,
    'copied_account_ids', v_trade.copied_account_ids,
    'copy_trading_group_id', v_trade.copy_trading_group_id,
    'participating_account_modes', public.copy_trade_public_participating_account_modes_json(v_trade),
    'points', v_trade.points,
    'entry_time', v_trade.entry_time,
    'exit_time', v_trade.exit_time,
    'entry_price', v_trade.entry_price,
    'exit_price', v_trade.exit_price,
    'trade_date', v_trade.trade_date,
    'duration_seconds', v_trade.duration_seconds,
    'duration_text', v_trade.duration_text,
    'image_url', v_trade.image_url,
    'image_crop', v_trade.image_crop,
    'reels', case when p_reel.id is null then null else jsonb_build_object(
      'id', p_reel.id,
      'user_id', p_reel.user_id,
      'video_url', p_reel.video_url,
      'thumbnail_url', p_reel.thumbnail_url,
      'duration_seconds', p_reel.duration_seconds,
      'trade_id', p_reel.trade_id,
      'visibility', p_reel.visibility
    ) end
  );
end;
$$;

comment on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) is
  'Feed trade card JSON. SECURITY DEFINER reads trades; enforces blocks, profile visibility, and public/follower trade rules.';

revoke all on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) from public;
grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to anon, authenticated;
