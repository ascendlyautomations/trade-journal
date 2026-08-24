-- Backend V2 Phase 4: Feed bootstrap (single JSON for Feed-owned data).
-- SECURITY INVOKER — relies on existing RLS.
-- Does NOT include session-owned fields (viewer, badges, prefs, entitlement).
-- following_ids_echo is an echo for Feed scope only — Session remains owner of SocialGraph.

create or replace function public.rpc_v1_feed_bootstrap(
  p_scope text default 'following',
  p_content_filter text default 'all',
  p_limit integer default 8,
  p_cursor timestamptz default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_scope text := lower(trim(coalesce(p_scope, 'following')));
  v_filter text := lower(trim(coalesce(p_content_filter, 'all')));
  v_limit integer := greatest(1, least(coalesce(p_limit, 8), 40));
  v_following uuid[] := '{}'::uuid[];
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
    select * from (
      select 'post'::text as kind, p.id, p.user_id as author_id, p.created_at
      from public.posts p
      where v_filter in ('all', 'trades')
        and p.user_id is distinct from v_uid
        and (p_cursor is null or p.created_at < p_cursor)
        and (
          (v_scope = 'following' and p.user_id = any (v_following))
          or (v_scope = 'global' and (cardinality(v_following) = 0 or not (p.user_id = any (v_following))))
        )
      order by p.created_at desc, p.id desc
      limit (v_limit + 1)
    ) trades_c
    union all
    select * from (
      select 'profile_post'::text, pp.id, pp.user_id, pp.created_at
      from public.profile_posts pp
      where v_filter in ('all', 'posts')
        and pp.user_id is distinct from v_uid
        and (p_cursor is null or pp.created_at < p_cursor)
        and (
          (v_scope = 'following' and pp.user_id = any (v_following))
          or (v_scope = 'global' and (cardinality(v_following) = 0 or not (pp.user_id = any (v_following))))
        )
      order by pp.created_at desc, pp.id desc
      limit (v_limit + 1)
    ) posts_c
    union all
    select * from (
      select 'achievement_post'::text, ap.id, ap.user_id, ap.created_at
      from public.achievement_posts ap
      join public.achievements a on a.id = ap.achievement_id
      where v_filter in ('all', 'achievements')
        and ap.user_id is distinct from v_uid
        and coalesce(a.is_public, true) = true
        and (p_cursor is null or ap.created_at < p_cursor)
        and (
          (v_scope = 'following' and ap.user_id = any (v_following))
          or (v_scope = 'global' and (cardinality(v_following) = 0 or not (ap.user_id = any (v_following))))
        )
      order by ap.created_at desc, ap.id desc
      limit (v_limit + 1)
    ) ach_c
    union all
    select * from (
      select 'reel'::text, r.id, r.user_id, r.created_at
      from public.reels r
      where v_filter in ('all', 'reels')
        and r.user_id is distinct from v_uid
        and (p_cursor is null or r.created_at < p_cursor)
        and (
          (v_scope = 'following' and r.user_id = any (v_following))
          or (v_scope = 'global' and (cardinality(v_following) = 0 or not (r.user_id = any (v_following))))
        )
        and (v_filter = 'reels' or r.trade_id is null)
      order by r.created_at desc, r.id desc
      limit (v_limit + 1)
    ) reels_c
  ),
  ranked as (
    select
      row_number() over (order by c.created_at desc, c.id desc) as rn,
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
      (select created_at from page order by rn desc limit 1) as next_ts
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
              'profiles', jsonb_build_object('username', pr.username, 'avatar_url', pr.avatar_url),
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
              'profiles', jsonb_build_object('username', ppr.username, 'avatar_url', ppr.avatar_url)
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
              'profiles', jsonb_build_object('username', apr.username, 'avatar_url', apr.avatar_url)
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
              'profiles', jsonb_build_object('username', rpr.username, 'avatar_url', rpr.avatar_url),
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
      left join public.posts p on pg.kind = 'post' and p.id = pg.id
      left join public.profiles pr on pr.id = p.user_id
      left join public.trades t on t.id = p.trade_id
      left join lateral (
        select r.*
        from public.reels r
        where r.trade_id = coalesce(p.trade_id, p.id)
        order by r.created_at desc
        limit 1
      ) tr on pg.kind = 'post'
      left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
      left join public.profiles ppr on ppr.id = pp.user_id
      left join public.achievement_posts ap on pg.kind = 'achievement_post' and ap.id = pg.id
      left join public.achievements a on a.id = ap.achievement_id
      left join public.profiles apr on apr.id = ap.user_id
      left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id
      left join public.profiles rpr on rpr.id = rl.user_id
      left join public.trades rt on rt.id = rl.trade_id
    ) built
    where item is not null
  ),
  id_sets as (
    select
      coalesce(array_agg(id) filter (where kind = 'post'), '{}'::uuid[]) as post_ids,
      coalesce(array_agg(id) filter (where kind = 'profile_post'), '{}'::uuid[]) as profile_ids,
      coalesce(array_agg(id) filter (where kind = 'achievement_post'), '{}'::uuid[]) as achievement_ids,
      coalesce(array_agg(id) filter (where kind = 'reel'), '{}'::uuid[]) as reel_ids,
      coalesce(array_agg(id), '{}'::uuid[]) as all_ids
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
        when (select has_more from page_meta) and (select next_ts from page_meta) is not null
          then to_char(timezone('utc', (select next_ts from page_meta)), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
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

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, timestamptz) is
  'Backend V2 Feed bootstrap — items + authors + engagement + stories. Session fields excluded.';

revoke all on function public.rpc_v1_feed_bootstrap(text, text, integer, timestamptz) from public;
grant execute on function public.rpc_v1_feed_bootstrap(text, text, integer, timestamptz) to authenticated;
