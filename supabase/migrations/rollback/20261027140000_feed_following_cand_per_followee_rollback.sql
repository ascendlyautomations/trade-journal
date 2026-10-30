-- Rollback: restore pre-20261027140000 Following cand (per-followee LATERAL) RPC body.
-- Source: production pg_get_functiondef equivalent on fobudrkniacatvilbofw (2026-10-27 read-only verify).
-- Apply manually on staging/production only after controlled rollback decision — not auto-run.

CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(p_scope text DEFAULT 'following'::text, p_content_filter text DEFAULT 'all'::text, p_limit integer DEFAULT 8, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$ declare
  v_uid uuid := (select auth.uid());
  v_scope text := lower(trim(coalesce(p_scope, 'following')));
  v_filter text := lower(trim(coalesce(p_content_filter, 'all')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 8), 40));
  v_following uuid[] := '{}'::uuid[];
  v_block_peers uuid[] := '{}'::uuid[];
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
  v_guest boolean := false;
begin
  if v_uid is null then
    -- Explore Mode guest: global discovery feed only (no Following, no blocks).
    v_scope := 'global';
    v_following := '{}'::uuid[];
    v_guest := true;
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

  if not v_guest and v_uid is not null then
    select public.get_active_block_peer_ids() into v_block_peers;
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
          and (v_guest or not (p.user_id = any (v_block_peers)))
          and public._v1_feed_before_cursor(
            p.created_at, 'post', p.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and p.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (p.user_id = any (v_following))))
          )
          and (
            not v_guest
            or (
              exists (
                select 1
                from public.trades_public_read tx
                where tx.id = p.trade_id
              )
              and exists (
                select 1
                from public.profiles pr
                where pr.id = p.user_id
                  and coalesce(pr.is_private, false) = false
              )
            )
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
          and (v_guest or not (pp.user_id = any (v_block_peers)))
          and public._v1_feed_before_cursor(
            pp.created_at, 'profile_post', pp.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and pp.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (pp.user_id = any (v_following))))
          )
          and (
            not v_guest
            or exists (
              select 1
              from public.profiles pr
              where pr.id = pp.user_id
                and coalesce(pr.is_private, false) = false
            )
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
          and (v_guest or not (ap.user_id = any (v_block_peers)))
          and coalesce(a.is_public, true) = true
          and public._v1_feed_before_cursor(
            ap.created_at, 'achievement_post', ap.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and ap.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (ap.user_id = any (v_following))))
          )
          and (
            not v_guest
            or exists (
              select 1
              from public.profiles pr
              where pr.id = ap.user_id
                and coalesce(pr.is_private, false) = false
            )
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
          and (v_guest or not (r.user_id = any (v_block_peers)))
          and public._v1_feed_before_cursor(
            r.created_at, 'reel', r.id,
            v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
          )
          and (
            (v_scope = 'following' and r.user_id = any (v_following))
            or (v_scope = 'global' and (cardinality(v_following) = 0 or not (r.user_id = any (v_following))))
          )
          and (v_filter = 'reels' or r.trade_id is null)
          and (not v_guest or coalesce(r.visibility, 'public') = 'public')
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
              'trades', public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)
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
              'metadata', case when v_guest then null else ap.metadata end,
              'achievements', case when a.id is null then null when v_guest then public._v1_guest_feed_achievement_projection(a) else to_jsonb(a) end,
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
        or v_guest or not (s.user_id = any (v_block_peers))
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
$function$;

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — excludes blocked authors via get_active_block_peer_ids (bidirectional user_blocks).';
