-- Profile pinned showcase — up to 3 cross-type pins (trade / profile_post / achievement).

-- =============================================================================
-- 1. Table
-- =============================================================================

create table if not exists public.profile_pinned_content (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  content_type text not null,
  content_id uuid not null,
  position smallint not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint profile_pinned_content_type_check
    check (content_type in ('trade', 'profile_post', 'achievement')),
  constraint profile_pinned_content_position_check
    check (position between 1 and 3),
  constraint profile_pinned_content_user_content_unique
    unique (user_id, content_type, content_id),
  constraint profile_pinned_content_user_position_unique
    unique (user_id, position)
);

create index if not exists profile_pinned_content_user_id_idx
  on public.profile_pinned_content (user_id, position);

comment on table public.profile_pinned_content is
  'Authoritative Profile showcase pins — max 3 items per user across trades, profile posts, achievements.';

-- =============================================================================
-- 2. Visibility helper — pins never bypass underlying content privacy
-- =============================================================================

create or replace function public.profile_pinned_item_visible(
  p_profile_id uuid,
  p_viewer_id uuid,
  p_is_own boolean,
  p_can_view boolean,
  p_content_type text,
  p_content_id uuid
)
returns boolean
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if not p_can_view then
    return false;
  end if;

  if p_content_type = 'trade' then
    return exists (
      select 1
      from public.trades t
      where t.id = p_content_id
        and t.user_id = p_profile_id
        and (p_is_own or coalesce(t.is_public, false) = true)
    );
  end if;

  if p_content_type = 'profile_post' then
    return exists (
      select 1
      from public.profile_posts pp
      where pp.id = p_content_id
        and pp.user_id = p_profile_id
    );
  end if;

  if p_content_type = 'achievement' then
    return exists (
      select 1
      from public.achievements a
      where a.id = p_content_id
        and a.user_id = p_profile_id
        and (p_is_own or coalesce(a.is_public, false) = true)
    );
  end if;

  return false;
end;
$$;

-- =============================================================================
-- 3. Bootstrap payload — single query, visibility-filtered previews
-- =============================================================================

create or replace function public.profile_pinned_content_bootstrap(
  p_profile_id uuid,
  p_viewer_id uuid,
  p_is_own boolean,
  p_can_view boolean
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  with pins as (
    select ppc.content_type, ppc.content_id, ppc.position
    from public.profile_pinned_content ppc
    where ppc.user_id = p_profile_id
    order by ppc.position asc
    limit 3
  ),
  resolved as (
    select
      p.content_type,
      p.content_id,
      p.position,
      case p.content_type
        when 'trade' then (
          select jsonb_build_object(
            'kind_label', 'Trade',
            'title', coalesce(
              case when coalesce(t.pnl, 0) >= 0 then '+' else '' end
                || trim(to_char(coalesce(t.pnl, 0), 'FM999,999,990.00')),
              'Trade'
            ),
            'subtitle', trim(
              coalesce(nullif(trim(t.ticker), ''), 'Trade')
              || case
                when nullif(trim(coalesce(t.direction, '')), '') is not null
                then ' · ' || initcap(trim(t.direction))
                else ''
              end
            ),
            'image_url', t.image_url,
            'body', left(trim(coalesce(t.public_description, t.notes, '')), 160)
          )
          from public.trades t
          where t.id = p.content_id
            and t.user_id = p_profile_id
            and (p_is_own or coalesce(t.is_public, false) = true)
        )
        when 'profile_post' then (
          select jsonb_build_object(
            'kind_label', 'Post',
            'title', left(trim(coalesce(pp.content, 'Post')), 120),
            'subtitle', null,
            'image_url', pp.image_url,
            'body', left(trim(coalesce(pp.content, '')), 160)
          )
          from public.profile_posts pp
          where pp.id = p.content_id
            and pp.user_id = p_profile_id
        )
        when 'achievement' then (
          select jsonb_build_object(
            'kind_label', 'Achievement',
            'title', coalesce(nullif(trim(a.title), ''), 'Achievement'),
            'subtitle', coalesce(nullif(trim(a.firm), ''), nullif(trim(a.achievement_type), '')),
            'image_url', a.image_url,
            'body', left(trim(coalesce(a.description, a.value_text, '')), 160),
            'value_text', case
              when a.value_numeric is not null then
                case when a.value_numeric >= 0 then '+' else '' end
                  || trim(to_char(a.value_numeric, 'FM999,999,990'))
              else nullif(trim(coalesce(a.value_text, '')), '')
            end
          )
          from public.achievements a
          where a.id = p.content_id
            and a.user_id = p_profile_id
            and (p_is_own or coalesce(a.is_public, false) = true)
        )
        else null
      end as preview
    from pins p
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'content_type', r.content_type,
        'content_id', r.content_id,
        'position', r.position,
        'preview', r.preview
      )
      order by r.position asc
    ),
    '[]'::jsonb
  )
  from resolved r
  where r.preview is not null;
$$;

-- =============================================================================
-- 4. Delete cascades — remove pins when underlying content is deleted
-- =============================================================================

create or replace function public.profile_pinned_content_cleanup()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_type text;
begin
  v_type := case tg_table_name
    when 'trades' then 'trade'
    when 'profile_posts' then 'profile_post'
    when 'achievements' then 'achievement'
    else null
  end;
  if v_type is null then
    return old;
  end if;
  delete from public.profile_pinned_content ppc
  where ppc.content_type = v_type
    and ppc.content_id = old.id;
  return old;
end;
$$;

drop trigger if exists profile_pinned_cleanup_trades on public.trades;
create trigger profile_pinned_cleanup_trades
  after delete on public.trades
  for each row execute function public.profile_pinned_content_cleanup();

drop trigger if exists profile_pinned_cleanup_profile_posts on public.profile_posts;
create trigger profile_pinned_cleanup_profile_posts
  after delete on public.profile_posts
  for each row execute function public.profile_pinned_content_cleanup();

drop trigger if exists profile_pinned_cleanup_achievements on public.achievements;
create trigger profile_pinned_cleanup_achievements
  after delete on public.achievements
  for each row execute function public.profile_pinned_content_cleanup();

-- =============================================================================
-- 5. RLS
-- =============================================================================

alter table public.profile_pinned_content enable row level security;

drop policy if exists "profile_pinned_content_select" on public.profile_pinned_content;
create policy "profile_pinned_content_select"
  on public.profile_pinned_content
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.profiles p
      where p.id = profile_pinned_content.user_id
        and (
          coalesce(p.is_private, false) = false
          or (
            auth.uid() is not null
            and exists (
              select 1
              from public.followers f
              where f.follower_id = auth.uid()
                and f.following_id = p.id
            )
          )
        )
    )
  );

drop policy if exists "profile_pinned_content_insert_own" on public.profile_pinned_content;
create policy "profile_pinned_content_insert_own"
  on public.profile_pinned_content
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "profile_pinned_content_update_own" on public.profile_pinned_content;
create policy "profile_pinned_content_update_own"
  on public.profile_pinned_content
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "profile_pinned_content_delete_own" on public.profile_pinned_content;
create policy "profile_pinned_content_delete_own"
  on public.profile_pinned_content
  for delete
  to authenticated
  using (user_id = auth.uid());

-- =============================================================================
-- 6. Mutations — pin / unpin / reorder (security definer for atomic swaps)
-- =============================================================================

create or replace function public.rpc_v1_profile_pin_content(
  p_content_type text,
  p_content_id uuid,
  p_replace_position int default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_type text := lower(trim(coalesce(p_content_type, '')));
  v_count int;
  v_position int;
  v_existing_position int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if v_type not in ('trade', 'profile_post', 'achievement') then
    raise exception 'invalid_content_type' using errcode = '22023';
  end if;
  if p_content_id is null then
    raise exception 'content_id_required' using errcode = '22023';
  end if;

  if v_type = 'trade' and not exists (
    select 1 from public.trades t where t.id = p_content_id and t.user_id = v_uid
  ) then
    raise exception 'content_not_owned' using errcode = '42501';
  end if;
  if v_type = 'profile_post' and not exists (
    select 1 from public.profile_posts pp where pp.id = p_content_id and pp.user_id = v_uid
  ) then
    raise exception 'content_not_owned' using errcode = '42501';
  end if;
  if v_type = 'achievement' and not exists (
    select 1 from public.achievements a where a.id = p_content_id and a.user_id = v_uid
  ) then
    raise exception 'content_not_owned' using errcode = '42501';
  end if;

  select ppc.position into v_existing_position
  from public.profile_pinned_content ppc
  where ppc.user_id = v_uid
    and ppc.content_type = v_type
    and ppc.content_id = p_content_id;

  if v_existing_position is not null then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1'),
      'data', jsonb_build_object(
        'pins', public.profile_pinned_content_bootstrap(v_uid, v_uid, true, true)
      )
    );
  end if;

  select count(*)::int into v_count
  from public.profile_pinned_content ppc
  where ppc.user_id = v_uid;

  if p_replace_position is not null then
    if p_replace_position < 1 or p_replace_position > 3 then
      raise exception 'invalid_replace_position' using errcode = '22023';
    end if;
    delete from public.profile_pinned_content
    where user_id = v_uid
      and position = p_replace_position;
    v_position := p_replace_position;
  elsif v_count >= 3 then
    raise exception 'pin_limit_reached' using errcode = 'P0001';
  else
    select min(pos)::int into v_position
    from generate_series(1, 3) pos
    where not exists (
      select 1
      from public.profile_pinned_content ppc
      where ppc.user_id = v_uid
        and ppc.position = pos
    );
    if v_position is null then
      raise exception 'pin_limit_reached' using errcode = 'P0001';
    end if;
  end if;

  insert into public.profile_pinned_content (user_id, content_type, content_id, position)
  values (v_uid, v_type, p_content_id, v_position);

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1'),
    'data', jsonb_build_object(
      'pins', public.profile_pinned_content_bootstrap(v_uid, v_uid, true, true)
    )
  );
end;
$$;

create or replace function public.rpc_v1_profile_unpin_content(
  p_content_type text,
  p_content_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_type text := lower(trim(coalesce(p_content_type, '')));
  v_removed_position int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  delete from public.profile_pinned_content ppc
  where ppc.user_id = v_uid
    and ppc.content_type = v_type
    and ppc.content_id = p_content_id
  returning ppc.position into v_removed_position;

  if v_removed_position is not null then
    update public.profile_pinned_content ppc
    set position = ppc.position - 1
    where ppc.user_id = v_uid
      and ppc.position > v_removed_position;
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1'),
    'data', jsonb_build_object(
      'pins', public.profile_pinned_content_bootstrap(v_uid, v_uid, true, true)
    )
  );
end;
$$;

create or replace function public.rpc_v1_profile_reorder_pinned(
  p_from_position int,
  p_to_position int
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_from_position is null or p_to_position is null
     or p_from_position < 1 or p_from_position > 3
     or p_to_position < 1 or p_to_position > 3
     or p_from_position = p_to_position
  then
    raise exception 'invalid_reorder' using errcode = '22023';
  end if;

  update public.profile_pinned_content
  set position = 0
  where user_id = v_uid and position = p_from_position;

  if not found then
    raise exception 'pin_not_found' using errcode = 'P0002';
  end if;

  update public.profile_pinned_content
  set position = p_from_position
  where user_id = v_uid and position = p_to_position;

  update public.profile_pinned_content
  set position = p_to_position
  where user_id = v_uid and position = 0;

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1'),
    'data', jsonb_build_object(
      'pins', public.profile_pinned_content_bootstrap(v_uid, v_uid, true, true)
    )
  );
end;
$$;

grant execute on function public.rpc_v1_profile_pin_content(text, uuid, int) to authenticated;
grant execute on function public.rpc_v1_profile_unpin_content(text, uuid) to authenticated;
grant execute on function public.rpc_v1_profile_reorder_pinned(int, int) to authenticated;

-- =============================================================================
-- 7. Extend profile bootstrap with pinned_content
-- =============================================================================

create or replace function public.rpc_v1_profile_bootstrap(
  p_identifier text,
  p_initial_tab text default 'trades',
  p_limit integer default 6,
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
  v_profile_id uuid;
  v_profile public.profiles%rowtype;
  v_limit integer := least(greatest(coalesce(p_limit, 6), 1), 24);
  v_tab text := lower(trim(coalesce(p_initial_tab, 'trades')));
  v_is_own boolean := false;
  v_is_following boolean := false;
  v_is_requested boolean := false;
  v_follows_you boolean := false;
  v_can_view boolean := false;
  v_followers_count integer := 0;
  v_following_count integer := 0;
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_trades jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_next_cursor text := null;
  v_public_stats jsonb := null;
  v_payout_total numeric := 0;
  v_section_counts jsonb;
  v_engagement jsonb := '{}'::jsonb;
  v_owned_room jsonb := null;
  v_active_stories jsonb := '[]'::jsonb;
  v_public_account_modes jsonb := '{}'::jsonb;
  v_pinned_content jsonb := '[]'::jsonb;
begin
  if p_identifier is null or trim(p_identifier) = '' then
    raise exception 'invalid_identifier' using errcode = '22023';
  end if;

  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_profile from public.profiles p where p.id = p_identifier::uuid;
  else
    select * into v_profile
    from public.profiles p
    where lower(trim(p.username)) = lower(trim(p_identifier));
  end if;

  if v_profile.id is null then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'found', false,
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      'data', jsonb_build_object('profile', null)
    );
  end if;

  v_profile_id := v_profile.id;
  v_is_own := v_viewer is not null and v_viewer = v_profile_id;

  if v_viewer is not null and not v_is_own then
    select exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = v_profile_id
    ) into v_is_following;

    select exists (
      select 1 from public.follow_requests fr
      where fr.requester_id = v_viewer and fr.target_id = v_profile_id
        and fr.status = 'pending'
    ) into v_is_requested;

    select exists (
      select 1 from public.followers f
      where f.follower_id = v_profile_id and f.following_id = v_viewer
    ) into v_follows_you;
  end if;

  v_can_view := v_is_own
    or coalesce(v_profile.is_private, false) = false
    or v_is_following;

  select count(*)::integer into v_followers_count
  from public.followers f where f.following_id = v_profile_id;

  select count(*)::integer into v_following_count
  from public.followers f where f.follower_id = v_profile_id;

  select jsonb_build_object(
    'id', r.id, 'name', r.name, 'slug', r.slug,
    'show_on_profile', coalesce(r.show_on_profile, true)
  )
  into v_owned_room
  from public.rooms r
  where r.owner_user_id = v_profile_id
  order by r.id
  limit 1;

  if v_can_view then
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id, 'user_id', s.user_id,
          'image_url', s.image_url, 'created_at', s.created_at
        )
        order by s.created_at desc
      ),
      '[]'::jsonb
    )
    into v_active_stories
    from public.stories s
    where s.user_id = v_profile_id
      and s.created_at > (timezone('utc', now()) - interval '24 hours');

    v_pinned_content := public.profile_pinned_content_bootstrap(
      v_profile_id, v_viewer, v_is_own, v_can_view
    );
  else
    v_active_stories := '[]'::jsonb;
    v_pinned_content := '[]'::jsonb;
  end if;

  v_section_counts := jsonb_build_object(
    'has_room', v_owned_room is not null,
    'has_active_story', coalesce(jsonb_array_length(v_active_stories), 0) > 0,
    'pinned_count', case when v_can_view then coalesce(jsonb_array_length(v_pinned_content), 0) else null end,
    'public_trades', case when v_can_view then (
      select count(*)::integer from public.trades t
      where t.user_id = v_profile_id and t.is_public is true
    ) else null end,
    'profile_posts', case when v_can_view then (
      select count(*)::integer from public.profile_posts pp where pp.user_id = v_profile_id
    ) else null end,
    'reels', case when v_can_view then (
      select count(*)::integer from public.reels r where r.user_id = v_profile_id
    ) else null end,
    'achievements', case when v_can_view then (
      select count(*)::integer from public.achievements a
      where a.user_id = v_profile_id and a.is_public is true
    ) else null end
  );

  select coalesce(sum(coalesce(a.value_numeric, 0)), 0)::numeric
  into v_payout_total
  from public.achievements a
  where a.user_id = v_profile_id
    and lower(trim(coalesce(a.achievement_type, ''))) like '%payout%';

  if v_can_view then
    with eligible as (
      select t.pnl, t.rr
      from public.trades t
      where t.user_id = v_profile_id
        and t.is_public is true
        and coalesce(t.mode, '') <> 'backtest'
        and coalesce(t.account_type, '') <> 'backtest'
    )
    select jsonb_build_object(
      'total_trades', count(*),
      'wins', count(*) filter (where coalesce(pnl, 0) > 0),
      'total_pnl', coalesce(sum(pnl), 0),
      'profit_factor', case
        when coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0) < 0
        then (
          coalesce(sum(pnl) filter (where coalesce(pnl, 0) > 0), 0)::numeric
          / abs(coalesce(sum(pnl) filter (where coalesce(pnl, 0) < 0), 0)::numeric)
        )
        else null
      end,
      'average_rr', case
        when count(*) filter (where rr is not null) > 0
        then avg(rr::numeric) filter (where rr is not null)
        else null
      end,
      'payout_total', v_payout_total
    )
    into v_public_stats
    from eligible;
  else
    v_public_stats := jsonb_build_object('payout_total', v_payout_total);
  end if;

  if v_can_view and v_tab = 'trades' then
    if p_cursor is not null and trim(p_cursor) <> '' then
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    end if;

    with page as (
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
    from ids;

    if v_has_more then
      select (to_char(tr.created_at, 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' || tr.id::text)
      into v_next_cursor
      from (
        select t.created_at, t.id
        from public.trades t
        where t.user_id = v_profile_id
          and t.is_public is true
          and (
            v_cursor_ts is null
            or (t.created_at, t.id) < (v_cursor_ts, v_cursor_id)
          )
        order by t.created_at desc, t.id desc
        limit v_limit
      ) tr
      order by tr.created_at asc, tr.id asc
      limit 1;
    end if;

    with trade_ids as (
      select (elem->>'id')::uuid as id
      from jsonb_array_elements(v_trades) elem
      where elem ? 'id'
    ),
    like_counts as (
      select tl.trade_id, count(*)::integer as like_count,
        bool_or(v_viewer is not null and tl.user_id = v_viewer) as liked_by_me
      from public.trade_likes tl
      inner join trade_ids ti on ti.id = tl.trade_id
      group by tl.trade_id
    ),
    comment_counts as (
      select tc.trade_id, count(*)::integer as comment_count
      from public.trade_comments tc
      inner join trade_ids ti on ti.id = tc.trade_id
      group by tc.trade_id
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
    left join like_counts lc on lc.trade_id = ti.id
    left join comment_counts cc on cc.trade_id = ti.id;
  end if;

  if v_can_view then
    select coalesce(jsonb_object_agg(a.id::text, a.mode), '{}'::jsonb)
    into v_public_account_modes
    from public.accounts a
    where a.user_id = v_profile_id
      and exists (
        select 1
        from public.trades t
        where a.id::text = nullif(trim(t.account_id), '')
          and t.is_public is true
      );
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'found', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_viewer
    ),
    'data', jsonb_build_object(
      'profile', jsonb_build_object(
        'id', v_profile.id, 'username', v_profile.username, 'name', v_profile.name,
        'bio', v_profile.bio, 'avatar_url', v_profile.avatar_url,
        'trading_style', v_profile.trading_style, 'trader_type', v_profile.trader_type,
        'primary_market', v_profile.primary_market, 'started_trading', v_profile.started_trading,
        'is_private', v_profile.is_private, 'created_at', v_profile.created_at
      ),
      'viewer', jsonb_build_object(
        'is_own_profile', v_is_own, 'can_view_trades', v_can_view,
        'is_following', v_is_following, 'is_requested', v_is_requested,
        'follows_you', v_follows_you
      ),
      'followers_count', v_followers_count,
      'following_count', v_following_count,
      'section_counts', v_section_counts,
      'public_stats', v_public_stats,
      'owned_room', v_owned_room,
      'active_stories', v_active_stories,
      'pinned_content', v_pinned_content,
      'public_account_modes', case when v_can_view then v_public_account_modes else null end,
      'active_tab', v_tab,
      'trades_page', case when v_tab = 'trades' and v_can_view then jsonb_build_object(
        'items', v_trades,
        'page_meta', jsonb_build_object(
          'limit', v_limit,
          'returned', coalesce(jsonb_array_length(v_trades), 0),
          'has_more', v_has_more,
          'next_cursor', v_next_cursor
        )
      ) else null end,
      'trade_engagement', case when v_tab = 'trades' and v_can_view then v_engagement else null end
    )
  );
end;
$$;

comment on function public.rpc_v1_profile_bootstrap(text, text, integer, text) is
  'Profile bootstrap — header, stats, pinned showcase (max 3), optional trades tab page.';
