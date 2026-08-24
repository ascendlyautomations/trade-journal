-- Phase B2: Optimize Feed bootstrap RPC — bounded branches, keyset cursor, set-based hydration.
-- SECURITY INVOKER preserved. Response contract keys unchanged; next_cursor may include kind|id suffix.

-- profile_posts lacked (user_id, created_at) — used by Following/Global feed branches.
create index if not exists profile_posts_user_id_created_at_idx
  on public.profile_posts (user_id, created_at desc, id desc);

create or replace function public._v1_feed_kind_rank(p_kind text)
returns integer
language sql
immutable
as $$
  select case p_kind
    when 'post' then 4
    when 'profile_post' then 3
    when 'achievement_post' then 2
    when 'reel' then 1
    else 0
  end;
$$;

revoke all on function public._v1_feed_kind_rank(text) from public;

-- Returns (cursor_ts, cursor_kind, cursor_id, cursor_kind_rank, legacy_timestamp_only).
create or replace function public._v1_feed_parse_cursor(p_cursor text)
returns table (
  cursor_ts timestamptz,
  cursor_kind text,
  cursor_id uuid,
  cursor_kind_rank integer,
  legacy_only boolean
)
language plpgsql
immutable
as $$
declare
  v_parts text[];
begin
  if p_cursor is null or btrim(p_cursor) = '' then
    return;
  end if;

  if position('|' in p_cursor) > 0 then
    v_parts := string_to_array(p_cursor, '|');
    if coalesce(array_length(v_parts, 1), 0) >= 3 then
      cursor_ts := v_parts[1]::timestamptz;
      cursor_kind := v_parts[2];
      cursor_id := v_parts[3]::uuid;
      cursor_kind_rank := public._v1_feed_kind_rank(cursor_kind);
      legacy_only := false;
      return next;
      return;
    end if;
  end if;

  cursor_ts := p_cursor::timestamptz;
  cursor_kind := null;
  cursor_id := null;
  cursor_kind_rank := null;
  legacy_only := true;
  return next;
end;
$$;

revoke all on function public._v1_feed_parse_cursor(text) from public;

create or replace function public._v1_feed_before_cursor(
  p_row_ts timestamptz,
  p_row_kind text,
  p_row_id uuid,
  p_cursor_ts timestamptz,
  p_cursor_kind text,
  p_cursor_id uuid,
  p_cursor_kind_rank integer,
  p_legacy_only boolean
)
returns boolean
language sql
stable
as $$
  select
    p_cursor_ts is null
    or (
      p_legacy_only
      and p_row_ts < p_cursor_ts
    )
    or (
      not coalesce(p_legacy_only, false)
      and (
        p_row_ts < p_cursor_ts
        or (
          p_row_ts = p_cursor_ts
          and (
            p_cursor_kind is null
            or public._v1_feed_kind_rank(p_row_kind) < p_cursor_kind_rank
            or (
              public._v1_feed_kind_rank(p_row_kind) = p_cursor_kind_rank
              and p_row_id < p_cursor_id
            )
          )
        )
      )
    );
$$;

revoke all on function public._v1_feed_before_cursor(
  timestamptz, text, uuid, timestamptz, text, uuid, integer, boolean
) from public;

create or replace function public.rpc_v1_feed_bootstrap(
  p_scope text default 'following',
  p_content_filter text default 'all',
  p_limit integer default 8,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := (select auth.uid());
  v_scope text := lower(trim(coalesce(p_scope, 'following')));
  v_filter text := lower(trim(coalesce(p_content_filter, 'all')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 8), 40));
  v_following uuid[] := '{}'::uuid[];
  v_cursor_ts timestamptz;
  v_cursor_kind text;
  v_cursor_id uuid;
  v_cursor_kind_rank integer;
  v_cursor_legacy boolean := true;
  v_include_trades boolean;
  v_include_posts boolean;
  v_include_achievements boolean;
  v_include_reels boolean;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_scope not in ('following', 'global') then
    v_scope := 'following';
  end if;

  if v_filter not in ('all', 'trades', 'reels', 'posts', 'achievements') then
    v_filter := 'all';
  end if;

  v_include_trades := v_filter in ('all', 'trades');
  v_include_posts := v_filter in ('all', 'posts');
  v_include_achievements := v_filter in ('all', 'achievements');
  v_include_reels := v_filter in ('all', 'reels');

  select c.cursor_ts, c.cursor_kind, c.cursor_id, c.cursor_kind_rank, c.legacy_only
  into v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
  from public._v1_feed_parse_cursor(p_cursor) c;

  select coalesce(array_agg(f.following_id), '{}'::uuid[])
  into v_following
  from public.followers f
  where f.follower_id = v_uid;

  if v_scope = 'following' and cardinality(v_following) = 0 then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_uid
      ),
      'data', jsonb_build_object(
        'scope', v_scope,
        'content_filter', v_filter,
        'items', '[]'::jsonb,
        'authors', '{}'::jsonb,
        'engagement', '{}'::jsonb,
        'stories', '[]'::jsonb,
        'story_authors', '{}'::jsonb,
        'next_cursor', null,
        'page_meta', jsonb_build_object('limit', v_limit, 'returned', 0, 'has_more', false),
        'following_ids_echo', '[]'::jsonb
      )
    );
  end if;

  with
  cand as (
    select kind, id, author_id, created_at
    from (
      select * from (
        select
          'post'::text as kind,
          p.id,
          p.user_id as author_id,
          p.created_at
        from public.posts p
        where v_include_trades
          and p.user_id is distinct from v_uid
          and public._v1_feed_before_cursor(
            p.created_at, 'post', p.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and p.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (p.user_id = any (v_following))))
          )
        order by p.created_at desc, p.id desc
        limit (v_limit + 1)
      ) trades_c
      union all
      select * from (
        select
          'profile_post'::text,
          pp.id,
          pp.user_id,
          pp.created_at
        from public.profile_posts pp
        where v_include_posts
          and pp.user_id is distinct from v_uid
          and public._v1_feed_before_cursor(
            pp.created_at, 'profile_post', pp.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and pp.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (pp.user_id = any (v_following))))
          )
        order by pp.created_at desc, pp.id desc
        limit (v_limit + 1)
      ) posts_c
      union all
      select * from (
        select
          'achievement_post'::text,
          ap.id,
          ap.user_id,
          ap.created_at
        from public.achievement_posts ap
        join public.achievements a on a.id = ap.achievement_id
        where v_include_achievements
          and ap.user_id is distinct from v_uid
          and coalesce(a.is_public, true) = true
          and public._v1_feed_before_cursor(
            ap.created_at, 'achievement_post', ap.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and ap.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (ap.user_id = any (v_following))))
          )
        order by ap.created_at desc, ap.id desc
        limit (v_limit + 1)
      ) ach_c
      union all
      select * from (
        select
          'reel'::text,
          r.id,
          r.user_id,
          r.created_at
        from public.reels r
        where v_include_reels
          and r.user_id is distinct from v_uid
          and public._v1_feed_before_cursor(
            r.created_at, 'reel', r.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and r.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (r.user_id = any (v_following))))
          )
          and (v_filter = 'reels' or r.trade_id is null)
        order by r.created_at desc, r.id desc
        limit (v_limit + 1)
      ) reels_c
    ) merged
  ),
  ranked as (
    select
      row_number() over (
        order by
          c.created_at desc,
          public._v1_feed_kind_rank(c.kind) desc,
          c.id desc
      ) as rn,
      c.kind,
      c.id,
      c.author_id,
      c.created_at
    from cand c
  ),
  page as (
    select * from ranked where rn <= v_limit
  ),
  page_meta as (
    select
      (select count(*)::integer from page) as returned,
      exists (select 1 from ranked where rn > v_limit) as has_more,
      (
        select jsonb_build_object(
          'kind', p.kind,
          'id', p.id,
          'created_at', p.created_at
        )
        from page p
        order by p.rn desc
        limit 1
      ) as last_row
  ),
  authors as (
    select coalesce(
      jsonb_object_agg(
        p.id::text,
        jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', p.username,
          'avatar_url', p.avatar_url
        )
      ),
      '{}'::jsonb
    ) as map
    from public.profiles p
    where p.id in (select distinct author_id from page)
  ),
  items as (
    select coalesce(jsonb_agg(item order by rn), '[]'::jsonb) as arr
    from (
      select
        pg.rn,
        case pg.kind
          when 'post' then jsonb_build_object(
            'kind', 'post',
            'id', p.id,
            'created_at', to_char(timezone('utc', p.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'author_id', p.user_id,
            'payload', jsonb_build_object(
              'id', p.id,
              'user_id', p.user_id,
              'trade_id', p.trade_id,
              'created_at', p.created_at,
              'pnl', p.pnl,
              'rr', p.rr,
              'image_url', p.image_url,
              'profiles', jsonb_build_object(
                'username', au.map -> p.user_id::text ->> 'username',
                'avatar_url', au.map -> p.user_id::text ->> 'avatar_url'
              ),
              'trades', case when t.id is null then null else jsonb_build_object(
                'created_at', t.created_at,
                'public_description', t.public_description,
                'user_id', t.user_id,
                'ticker', t.ticker,
                'direction', t.direction,
                'account_type', t.account_type,
                'mode', t.mode,
                'trade_mode', t.trade_mode,
                'copied_account_ids', t.copied_account_ids,
                'copy_trading_group_id', t.copy_trading_group_id,
                'points', t.points,
                'entry_time', t.entry_time,
                'exit_time', t.exit_time,
                'entry_price', t.entry_price,
                'exit_price', t.exit_price,
                'trade_date', t.trade_date,
                'duration_seconds', t.duration_seconds,
                'duration_text', t.duration_text,
                'reels', case when tr.id is null then null else jsonb_build_object(
                  'id', tr.id,
                  'user_id', tr.user_id,
                  'video_url', tr.video_url,
                  'thumbnail_url', tr.thumbnail_url,
                  'duration_seconds', tr.duration_seconds,
                  'trade_id', tr.trade_id,
                  'visibility', tr.visibility
                ) end
              ) end
            )
          )
          when 'profile_post' then jsonb_build_object(
            'kind', 'profile_post',
            'id', pp.id,
            'created_at', to_char(timezone('utc', pp.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'author_id', pp.user_id,
            'payload', jsonb_build_object(
              'id', pp.id,
              'user_id', pp.user_id,
              'content', pp.content,
              'image_url', pp.image_url,
              'created_at', pp.created_at,
              'room_id', pp.room_id,
              'room_name', pp.room_name,
              'room_logo', pp.room_logo,
              'room_description', pp.room_description,
              'profiles', jsonb_build_object(
                'username', au.map -> pp.user_id::text ->> 'username',
                'avatar_url', au.map -> pp.user_id::text ->> 'avatar_url'
              )
            )
          )
          when 'achievement_post' then jsonb_build_object(
            'kind', 'achievement_post',
            'id', ap.id,
            'created_at', to_char(timezone('utc', ap.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'author_id', ap.user_id,
            'payload', jsonb_build_object(
              'id', ap.id,
              'user_id', ap.user_id,
              'achievement_id', ap.achievement_id,
              'created_at', ap.created_at,
              'metadata', ap.metadata,
              'achievements', case when a.id is null then null else to_jsonb(a) end,
              'profiles', jsonb_build_object(
                'username', au.map -> ap.user_id::text ->> 'username',
                'avatar_url', au.map -> ap.user_id::text ->> 'avatar_url'
              )
            )
          )
          when 'reel' then jsonb_build_object(
            'kind', 'reel',
            'id', rl.id,
            'created_at', to_char(timezone('utc', rl.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'author_id', rl.user_id,
            'payload', jsonb_build_object(
              'id', rl.id,
              'user_id', rl.user_id,
              'caption', rl.caption,
              'video_url', rl.video_url,
              'thumbnail_url', rl.thumbnail_url,
              'duration_seconds', rl.duration_seconds,
              'visibility', rl.visibility,
              'trade_id', rl.trade_id,
              'kind', rl.kind,
              'created_at', rl.created_at,
              'profiles', jsonb_build_object(
                'username', au.map -> rl.user_id::text ->> 'username',
                'avatar_url', au.map -> rl.user_id::text ->> 'avatar_url'
              ),
              'trades', case when rt.id is null then null else jsonb_build_object(
                'id', rt.id,
                'public_description', rt.public_description,
                'is_public', rt.is_public,
                'ticker', rt.ticker,
                'direction', rt.direction,
                'pnl', rt.pnl,
                'rr', rt.rr
              ) end
            )
          )
        end as item
      from page pg
      cross join authors au
      left join public.posts p on pg.kind = 'post' and p.id = pg.id
      left join public.trades t on t.id = p.trade_id
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
      left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
      left join public.achievement_posts ap on pg.kind = 'achievement_post' and ap.id = pg.id
      left join public.achievements a on a.id = ap.achievement_id
      left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id
      left join public.trades rt on rt.id = rl.trade_id
    ) built
    where item is not null
  ),
  id_sets as (
    select
      coalesce(array_agg(id) filter (where kind = 'post'), '{}'::uuid[]) as post_ids,
      coalesce(array_agg(id) filter (where kind = 'profile_post'), '{}'::uuid[]) as profile_ids,
      coalesce(array_agg(id) filter (where kind = 'achievement_post'), '{}'::uuid[]) as achievement_ids,
      coalesce(array_agg(id) filter (where kind = 'reel'), '{}'::uuid[]) as reel_ids
    from page
  ),
  eng_rows as (
    select e.*
    from id_sets s
    cross join lateral public.feed_engagement_counts(
      s.post_ids, s.profile_ids, s.achievement_ids, s.reel_ids
    ) e
  ),
  eng_map as (
    select coalesce(
      (
        select jsonb_object_agg(
          x.content_id::text,
          jsonb_build_object(
            'like_count', x.like_count,
            'comment_count', x.comment_count,
            'liked_by_viewer', x.liked_by_me
          )
        )
        from (
          select
            i.id as content_id,
            coalesce(e.like_count, 0) as like_count,
            coalesce(e.comment_count, 0) as comment_count,
            coalesce(e.liked_by_me, false) as liked_by_me
          from page i
          left join eng_rows e on e.content_id = i.id
        ) x
      ),
      '{}'::jsonb
    ) as map
  ),
  story_rows as (
    select s.id, s.user_id, s.image_url, s.created_at
    from public.stories s
    where v_scope = 'following'
      and s.user_id = any (array_append(v_following, v_uid))
      and s.created_at > (timezone('utc', now()) - interval '24 hours')
  ),
  stories_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'user_id', s.user_id,
          'image_url', s.image_url,
          'created_at', to_char(timezone('utc', s.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        )
        order by s.created_at desc
      ),
      '[]'::jsonb
    ) as arr
    from story_rows s
  ),
  story_authors as (
    select coalesce(
      jsonb_object_agg(
        p.id::text,
        jsonb_build_object(
          'id', p.id,
          'username', p.username,
          'display_name', p.username,
          'avatar_url', p.avatar_url
        )
      ),
      '{}'::jsonb
    ) as map
    from public.profiles p
    where p.id in (select distinct user_id from story_rows)
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'scope', v_scope,
      'content_filter', v_filter,
      'items', (select arr from items),
      'authors', (select map from authors),
      'engagement', (select map from eng_map),
      'stories', (select arr from stories_json),
      'story_authors', (select map from story_authors),
      'next_cursor', case
        when (select has_more from page_meta)
          and (select last_row from page_meta) is not null
          then (
            to_char(
              timezone('utc', ((select last_row from page_meta) ->> 'created_at')::timestamptz),
              'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            )
            || '|'
            || ((select last_row from page_meta) ->> 'kind')
            || '|'
            || ((select last_row from page_meta) ->> 'id')
          )
        else null
      end,
      'page_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', (select returned from page_meta),
        'has_more', (select has_more from page_meta)
      ),
      'following_ids_echo', to_jsonb(coalesce(v_following, '{}'::uuid[]))
    )
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — Phase B2 optimized plan. Keyset cursor: ISO|kind|uuid.';

-- Drop timestamptz overload if present from Phase 4.
drop function if exists public.rpc_v1_feed_bootstrap(text, text, integer, timestamptz);

revoke all on function public.rpc_v1_feed_bootstrap(text, text, integer, text) from public;
grant execute on function public.rpc_v1_feed_bootstrap(text, text, integer, text) to authenticated;
