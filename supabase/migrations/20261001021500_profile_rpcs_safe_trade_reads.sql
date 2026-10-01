-- Profile RPCs are SECURITY INVOKER. After authenticated lost table SELECT on
-- public.trades, `SELECT t.*` and private columns (notes, account_id) raise
-- 42501 permission denied for table trades.
--
-- Public/non-owner reads use trades_public_read (social columns only).
-- Owner journal rows stay inside SECURITY DEFINER helpers that require
-- auth.uid() = the profile/trade owner and never grant table SELECT back.

-- ---------------------------------------------------------------------------
-- Owner-only note snippet used by pin previews. Direct callers who are not
-- the trade owner get null. Does not return strategy/emotion/account fields.
-- ---------------------------------------------------------------------------

create or replace function public.profile_owner_note_snippet(p_trade_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when auth.uid() is not null and auth.uid() = t.user_id then
      nullif(left(trim(coalesce(t.notes, '')), 360), '')
    else
      null
  end
  from public.trades t
  where t.id = p_trade_id;
$$;

comment on function public.profile_owner_note_snippet(uuid) is
  'Owner-only 360-char notes snippet. Non-owners receive null.';

revoke all on function public.profile_owner_note_snippet(uuid) from public;
grant execute on function public.profile_owner_note_snippet(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Profile trade list rows. Owner: full row (journal stays on the owner path).
-- Everyone else: trades_public_read projection only.
-- ---------------------------------------------------------------------------

create or replace function public.profile_visible_trade_rows(
  p_profile_id uuid,
  p_cursor_ts timestamptz,
  p_cursor_id uuid,
  p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 24), 1), 100);
begin
  if p_profile_id is null or not public.profile_viewer_can_view_trades(p_profile_id) then
    return '[]'::jsonb;
  end if;

  if auth.uid() = p_profile_id then
    return coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc)
      from (
        select t.*
        from public.trades t
        where t.user_id = auth.uid()
          and coalesce(t.is_public, false) = true
          and (
            p_cursor_ts is null
            or (t.created_at, t.id) < (p_cursor_ts, p_cursor_id)
          )
        order by t.created_at desc, t.id desc
        limit v_limit
      ) x
    ), '[]'::jsonb);
  end if;

  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc)
    from (
      select t.*
      from public.trades_public_read t
      where t.user_id = p_profile_id
        and (
          p_cursor_ts is null
          or (t.created_at, t.id) < (p_cursor_ts, p_cursor_id)
        )
      order by t.created_at desc, t.id desc
      limit v_limit
    ) x
  ), '[]'::jsonb);
end;
$$;

comment on function public.profile_visible_trade_rows(uuid, timestamptz, uuid, integer) is
  'Profile trade page rows. Non-owners receive trades_public_read columns only.';

revoke all on function public.profile_visible_trade_rows(uuid, timestamptz, uuid, integer) from public;
grant execute on function public.profile_visible_trade_rows(uuid, timestamptz, uuid, integer) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- TradeSummary wire for profile tab v2. Returns the existing summary object,
-- never the raw trade row. note_preview uses notes only when auth.uid() owns it.
-- ---------------------------------------------------------------------------

create or replace function public.profile_visible_trade_summary(p_trade_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_trade public.trades%rowtype;
begin
  select * into v_trade
  from public.trades t
  where t.id = p_trade_id;

  if v_trade.id is null then
    return null;
  end if;

  if auth.uid() is distinct from v_trade.user_id
     and not (
       coalesce(v_trade.is_public, false)
       and public.profile_viewer_can_view_trades(v_trade.user_id)
     )
  then
    return null;
  end if;

  return public.trade_summary_json(v_trade, auth.uid());
end;
$$;

comment on function public.profile_visible_trade_summary(uuid) is
  'Viewer-safe TradeSummary JSON. Does not return journal columns except the owner note_preview.';

revoke all on function public.profile_visible_trade_summary(uuid) from public;
grant execute on function public.profile_visible_trade_summary(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Account-mode map already returned by profile bootstrap. Reads account_id
-- only inside this definer; callers still cannot SELECT that column.
-- ---------------------------------------------------------------------------

create or replace function public.profile_public_account_modes(p_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not public.profile_viewer_can_view_trades(p_profile_id) then null
    else (
      select coalesce(jsonb_object_agg(a.id::text, a.mode), '{}'::jsonb)
      from public.accounts a
      where a.user_id = p_profile_id
        and exists (
          select 1
          from public.trades t
          where a.id::text = nullif(trim(t.account_id), '')
            and t.user_id = p_profile_id
            and coalesce(t.is_public, false) = true
        )
    )
  end;
$$;

comment on function public.profile_public_account_modes(uuid) is
  'Public-trade account mode map for a viewable profile. No journal columns.';

revoke all on function public.profile_public_account_modes(uuid) from public;
grant execute on function public.profile_public_account_modes(uuid) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Statistics helper reads account_id. Keep the projection, but only for a
-- viewer who may see that profile, and do not return account_id.
-- ---------------------------------------------------------------------------

create or replace function public.profile_statistics_public_trades(p_profile_id uuid)
returns table(
  pnl numeric,
  created_at timestamp with time zone,
  trade_id uuid,
  is_long boolean,
  session_raw text,
  acct_mode text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.pnl,
    t.created_at,
    t.id,
    (lower(coalesce(t.direction, '')) = 'long'),
    coalesce(t.session, ''),
    public.profile_statistics_resolve_account_mode(a.mode, t.account_type, t.mode)
  from public.trades t
  left join public.accounts a
    on a.id::text = nullif(trim(t.account_id::text), '')
    and a.user_id = t.user_id
  where public.profile_viewer_can_view_trades(p_profile_id)
    and t.user_id = p_profile_id
    and coalesce(t.is_public, false) = true;
$$;

comment on function public.profile_statistics_public_trades(uuid) is
  'Public-trade stats inputs for a viewable profile. SECURITY DEFINER; no journal columns in the result.';

-- Explore cards use the same account-mode join. Keep RLS-equivalent visibility
-- inside the definer so private profiles the caller cannot see stay excluded.
create or replace function public.explore_profile_public_win_rates(p_profile_ids uuid[])
returns table(user_id uuid, win_rate numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.user_id,
    case
      when count(*) > 0 then round(
        count(*) filter (where coalesce(t.pnl, 0) > 0)::numeric / count(*)::numeric,
        8
      )
      else null
    end as win_rate
  from public.trades t
  left join public.accounts a
    on a.id::text = nullif(trim(t.account_id::text), '')
    and a.user_id = t.user_id
  where t.user_id = any (p_profile_ids)
    and public.profile_viewer_can_view_trades(t.user_id)
    and coalesce(t.is_public, false) = true
    and coalesce(
      public.profile_statistics_resolve_account_mode(a.mode, t.account_type, t.mode),
      ''
    ) <> 'backtest'
  group by t.user_id;
$$;

comment on function public.explore_profile_public_win_rates(uuid[]) is
  'Public-trade win rates for viewable profiles. SECURITY DEFINER; returns only user_id and win_rate.';

-- ---------------------------------------------------------------------------
-- Patch existing invoker functions in place. Fail the migration if the
-- expected statements are no longer present.
-- ---------------------------------------------------------------------------

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'profile_pinned_content_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_profile_id uuid, p_viewer_id uuid, p_is_own boolean, p_can_view boolean';

  if position('coalesce(t.public_description, t.notes, '''')' in src) > 0 then
    updated := replace(
      src,
      'coalesce(t.public_description, t.notes, '''')',
      'coalesce(t.public_description, public.profile_owner_note_snippet(t.id), '''')'
    );
    execute updated;
  elsif position('profile_owner_note_snippet' in src) = 0 then
    raise exception 'profile_pinned_content_bootstrap did not contain the notes fallback';
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_identifier text, p_initial_tab text, p_limit integer, p_cursor text';

  updated := replace(
    src,
    $old$    with page as (
      select t.*
      from public.trades t
      where t.user_id = v_profile_id
        and t.is_public is true
        and (
          v_cursor_ts is null
          or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
        )
      order by t.created_at desc, t.id desc
      limit v_limit + 1
    ),
    trimmed as (select * from page limit v_limit),
    ids as (select array_agg(id) as trade_ids from trimmed)
    select
      coalesce(
        (select jsonb_agg(to_jsonb(tr) order by tr.created_at desc, tr.id desc) from trimmed tr),
        '[]'::jsonb
      ),
      (select count(*) > v_limit from page)
    into v_trades, v_has_more
    from ids;$old$,
    $new$    select
      public.profile_visible_trade_rows(v_profile_id, v_cursor_ts, v_cursor_id, v_limit),
      (
        select count(*) > v_limit
        from (
          select 1
          from public.trades_public_read t
          where t.user_id = v_profile_id
            and (
              v_cursor_ts is null
              or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
            )
          limit v_limit + 1
        ) page_probe
      )
    into v_trades, v_has_more;$new$
  );
  if updated = src and position('profile_visible_trade_rows' in src) = 0 then
    raise exception 'rpc_v1_profile_bootstrap trade page query was not found';
  end if;
  if updated <> src then
    src := updated;
  end if;

  updated := replace(
    src,
    $old$    select coalesce(jsonb_object_agg(a.id::text, a.mode), '{}'::jsonb)
    into v_public_account_modes
    from public.accounts a
    where a.user_id = v_profile_id
      and exists (
        select 1
        from public.trades t
        where a.id::text = nullif(trim(t.account_id), '')
          and t.is_public is true
      );$old$,
    $new$    v_public_account_modes := public.profile_public_account_modes(v_profile_id);$new$
  );
  if updated = src and position('profile_public_account_modes' in src) = 0 then
    raise exception 'rpc_v1_profile_bootstrap account_id lookup was not found';
  end if;
  if updated <> src then
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_tab_trades_v2'
    and pg_get_function_identity_arguments(p.oid) =
      'p_profile_id uuid, p_limit integer, p_cursor text';

  updated := replace(
    src,
    $old$  WITH page AS (
    SELECT t.*
    FROM public.trades t
    WHERE t.user_id = p_profile_id
      AND t.is_public IS TRUE
      AND (
        v_cursor_ts IS NULL
        OR (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
      )
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT v_limit + 1
  ),
  trimmed AS (
    SELECT * FROM page LIMIT v_limit
  )
  SELECT
    coalesce(
      jsonb_agg(
        public.trade_summary_json(tr, v_viewer)
        ORDER BY tr.created_at DESC, tr.id DESC
      ),
      '[]'::jsonb
    ),
    (SELECT count(*) > v_limit FROM page)
  INTO v_items, v_has_more
  FROM trimmed tr;$old$,
    $new$  WITH page AS (
    SELECT t.id, t.created_at
    FROM public.trades_public_read t
    WHERE t.user_id = p_profile_id
      AND (
        v_cursor_ts IS NULL
        OR (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
      )
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT v_limit + 1
  ),
  trimmed AS (
    SELECT * FROM page LIMIT v_limit
  )
  SELECT
    coalesce(
      jsonb_agg(
        public.profile_visible_trade_summary(tr.id)
        ORDER BY tr.created_at DESC, tr.id DESC
      ),
      '[]'::jsonb
    ),
    (SELECT count(*) > v_limit FROM page)
  INTO v_items, v_has_more
  FROM trimmed tr;$new$
  );
  if updated = src and position('profile_visible_trade_summary' in src) = 0 then
    raise exception 'rpc_v1_profile_tab_trades_v2 trade page query was not found';
  end if;
  if updated <> src then
    execute updated;
  end if;

  select pg_get_functiondef(p.oid) into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_tab_trades'
    and pg_get_function_identity_arguments(p.oid) =
      'p_profile_id uuid, p_limit integer, p_cursor text';

  updated := replace(
    src,
    $old$  with page as (
    select t.*
    from public.trades t
    where t.user_id = p_profile_id
      and t.is_public is true$old$,
    $new$  with page as (
    select t.*
    from public.trades_public_read t
    where t.user_id = p_profile_id
      and t.is_public is true$new$
  );
  if updated = src and position('trades_public_read' in src) = 0 then
    raise exception 'rpc_v1_profile_tab_trades select t.* was not found';
  end if;
  if updated <> src then
    execute updated;
  end if;
end
$mig$;
