-- Explore Mode: anonymous read-only community surfaces (narrow RPC grants, no broad table SELECT).

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
    -- Explore Mode guest: global discovery feed only (no Following, no blocks).
    v_scope := 'global';
    v_following := '{}'::uuid[];
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

  if v_uid is not null then
    select coalesce(array_agg(f.following_id), '{}'::uuid[])
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

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
          and not public.users_have_active_block(v_uid, p.user_id)
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
          and not public.users_have_active_block(v_uid, pp.user_id)
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
          and not public.users_have_active_block(v_uid, ap.user_id)
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
          and not public.users_have_active_block(v_uid, r.user_id)
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
              'image_crop', p.image_crop,
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
                'image_url', t.image_url,
                'image_crop', t.image_crop,
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
              'image_crop', pp.image_crop,
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
      and (
        s.user_id = v_uid
        or not public.users_have_active_block(v_uid, s.user_id)
      )
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




-- Explore bootstrap guest access
create or replace function public.rpc_v1_explore_bootstrap(
  p_trader_limit int default 24,
  p_room_limit int default 12,
  p_trader_offset int default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_trader_limit int := greatest(least(coalesce(p_trader_limit, 24), 48), 1);
  v_room_limit int := greatest(least(coalesce(p_room_limit, 12), 50), 1);
  v_trader_offset int := greatest(coalesce(p_trader_offset, 0), 0);
  v_traders jsonb := '[]'::jsonb;
  v_rooms jsonb := '[]'::jsonb;
  v_social jsonb := '{}'::jsonb;
  v_following jsonb := '[]'::jsonb;
  v_activity jsonb := '{}'::jsonb;
  v_next_cursor text := null;
  v_profile_ids uuid[];
begin
  if v_uid is null then
    v_following := '[]'::jsonb;
  else
  select coalesce(
    jsonb_agg(f.following_id::text order by f.following_id),
    '[]'::jsonb
  )
  into v_following
  from public.followers f
  where f.follower_id = v_uid;
  end if;

  with trader_page as (
    select
      p.id,
      p.username,
      p.name,
      p.bio,
      p.avatar_url,
      p.trader_type,
      p.trading_style,
      p.primary_market,
      p.started_trading,
      p.is_private,
      p.created_at
    from public.profiles p
    where p.username is not null
      and trim(p.username) <> ''
      and coalesce(p.is_private, false) = false
      and (v_uid is null or p.id <> v_uid)
      and not exists (
        select 1 from public.followers f
        where f.follower_id = v_uid
          and f.following_id = p.id
      )
    order by p.created_at desc
    offset v_trader_offset
    limit v_trader_limit + 1
  ),
  trimmed as (
    select * from trader_page
    limit v_trader_limit
  ),
  trader_meta as (
    select count(*) as cnt from trader_page
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', t.id,
            'username', t.username,
            'name', t.name,
            'bio', t.bio,
            'avatar_url', t.avatar_url,
            'trader_type', t.trader_type,
            'trading_style', t.trading_style,
            'primary_market', t.primary_market,
            'started_trading', t.started_trading,
            'is_private', coalesce(t.is_private, false),
            'created_at', to_char(t.created_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          )
          order by t.created_at desc
        )
        from trimmed t
      ),
      '[]'::jsonb
    ),
    case
      when (select cnt from trader_meta) > v_trader_limit
        then (v_trader_offset + v_trader_limit)::text
      else null
    end,
    coalesce((select array_agg(t.id) from trimmed t), '{}'::uuid[])
  into v_traders, v_next_cursor, v_profile_ids;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'name', r.name,
        'description', r.description,
        'slug', r.slug,
        'member_count', r.member_count,
        'image_url', r.image_url
      )
      order by r.member_count desc nulls last, r.name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from (
    select
      pr.id,
      pr.name,
      pr.description,
      pr.slug,
      pr.member_count,
      rm.image_url
    from public.popular_trade_rooms(v_room_limit) pr
    left join public.rooms rm on rm.id = pr.id
  ) r;

  if coalesce(array_length(v_profile_ids, 1), 0) > 0 then
    select coalesce(
      jsonb_object_agg(
        sc.profile_id::text,
        jsonb_build_object(
          'followers', sc.followers_count,
          'following', sc.following_count
        )
      ),
      '{}'::jsonb
    )
    into v_social
    from public.explore_social_counts(v_profile_ids) sc;

    with summaries as (
      select
        m.user_id,
        m.trade_count,
        m.last_trade_at
      from public.explore_trade_meta_aggregates(1500) m
      where m.row_kind = 'summary'
        and m.user_id = any (v_profile_ids)
    )
    select coalesce(
      jsonb_object_agg(
        s.user_id::text,
        jsonb_build_object(
          'trade_count', s.trade_count,
          'last_trade_at', case
            when s.last_trade_at is null then null
            else to_char(s.last_trade_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          end
        )
      ),
      '{}'::jsonb
    )
    into v_activity
    from summaries s;
  end if;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid::text
    ),
    'data', jsonb_build_object(
      'traders', v_traders,
      'rooms', v_rooms,
      'social_counts', v_social,
      'following_ids', v_following,
      'activity_meta', v_activity,
      'traders_next_cursor', v_next_cursor
    )
  );
end;
$$;



-- Public Trade Room read-only bootstrap for Explore Mode guests (member-only rooms excluded).
create or replace function public.rpc_v1_public_room_guest_bootstrap(
  p_room_id uuid,
  p_section_id uuid default null,
  p_limit integer default 40,
  p_cursor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_room public.rooms%rowtype;
  v_limit integer := greatest(1, least(coalesce(p_limit, 40), 80));
  v_section_id uuid := p_section_id;
  v_messages jsonb := '[]'::jsonb;
  v_next_cursor text := null;
  v_has_more boolean := false;
begin
  select * into v_room from public.rooms r where r.id = p_room_id;
  if v_room.id is null then
    raise exception 'room_not_found' using errcode = 'P0002';
  end if;

  if coalesce(v_room.is_private, false) = true
     or coalesce(v_room.show_on_profile, true) = false
     or lower(trim(coalesce(v_room.slug, ''))) = 'tradetraxs-beta'
  then
    raise exception 'room_not_public' using errcode = '42501';
  end if;

  if v_section_id is null then
    select s.id into v_section_id
    from public.room_sections s
    where s.room_id = p_room_id
    order by s.position asc nulls last, s.id asc
    limit 1;
  end if;

  with filtered as (
    select msg.id, msg.created_at
    from public.room_messages msg
    where msg.room_id = p_room_id
      and msg.pinned = false
      and (
        v_section_id is null
        or msg.section_id = v_section_id
        or msg.section_id is null
      )
    order by msg.created_at desc, msg.id desc
    limit (v_limit + 1)
  ),
  page_ids as (
    select f.id, f.created_at
    from filtered f
    order by f.created_at desc, f.id desc
    limit v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          public.rpc_v1_room_bootstrap_message_row(p.id)
          order by p.created_at asc, p.id asc
        )
        from page_ids p
      ),
      '[]'::jsonb
    ),
    (select count(*) > v_limit from filtered),
    (
      select
        to_char(timezone('utc', oldest.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        || '|' || oldest.id::text
      from (
        select p2.created_at, p2.id
        from page_ids p2
        order by p2.created_at asc, p2.id asc
        limit 1
      ) oldest
    )
  into v_messages, v_has_more, v_next_cursor;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'guest', true,
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    ),
    'data', jsonb_build_object(
      'room', jsonb_build_object(
        'id', v_room.id,
        'name', v_room.name,
        'slug', v_room.slug,
        'description', v_room.description,
        'image_url', v_room.image_url,
        'room_kind', v_room.room_kind,
        'join_policy', v_room.join_policy,
        'is_private', coalesce(v_room.is_private, false)
      ),
      'messages', v_messages,
      'next_cursor', case when v_has_more then v_next_cursor else null end,
      'can_send_messages', false
    )
  );
end;
$$;

revoke all on function public.rpc_v1_public_room_guest_bootstrap(uuid, uuid, integer, text) from public;
grant execute on function public.rpc_v1_public_room_guest_bootstrap(uuid, uuid, integer, text) to anon, authenticated;

comment on function public.rpc_v1_public_room_guest_bootstrap is
  'Explore Mode guest read-only public Trade Room transcript (no membership required).';

