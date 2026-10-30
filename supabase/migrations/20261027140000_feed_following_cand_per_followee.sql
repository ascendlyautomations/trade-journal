-- Following feed: per-followee lateral top-(limit+1) in cand branches (Global path unchanged).
-- Validate on staging clone + supabase/staging/benchmark before production apply.

do $mig$
declare
  src text;
  updated text;
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

  if position('post_merge' in src) > 0 then
    if position('profile_post_merge' in src) = 0
       or position('achievement_post_merge' in src) = 0
       or position('reel_merge' in src) = 0 then
      raise exception 'rpc_v1_feed_bootstrap partial following cand patch (fail closed)';
    end if;
    return;
  end if;

  if position('get_active_block_peer_ids()' in src) = 0 then
    raise exception 'rpc_v1_feed_bootstrap must include get_active_block_peer_ids before cand rewrite';
  end if;

  if position('users_have_active_block(v_uid,' in src) > 0 then
    raise exception 'rpc_v1_feed_bootstrap must use get_active_block_peer_ids before following cand rewrite';
  end if;

  updated := src;

  updated := replace(
    updated,
    $old_post$
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
$old_post$,
    $new_post$
      select * from (
        select kind, id, author_id, created_at
        from (
          (
          select
            'post'::text as kind,
            p.id,
            p.user_id as author_id,
            p.created_at
          from public.posts p
          where v_scope = 'global'
            and v_include_trades
            and p.user_id is distinct from v_uid
            and (v_guest or not (p.user_id = any (v_block_peers)))
            and public._v1_feed_before_cursor(
              p.created_at, 'post', p.id,
              v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
            )
            and (cardinality(v_following) = 0 or not (p.user_id = any (v_following)))
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
          )
          union all
          select lat.kind, lat.id, lat.author_id, lat.created_at
          from unnest(
            case when v_scope = 'following' then v_following else '{}'::uuid[] end
          ) as fid
          cross join lateral (
            select
              'post'::text as kind,
              p.id,
              p.user_id as author_id,
              p.created_at
            from public.posts p
            where v_include_trades
              and p.user_id = fid
              and p.user_id is distinct from v_uid
              and (v_guest or not (p.user_id = any (v_block_peers)))
              and public._v1_feed_before_cursor(
                p.created_at, 'post', p.id,
                v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
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
          ) lat
        ) post_merge
        order by created_at desc, id desc
        limit (v_limit + 1)
      ) trades_c
$new_post$
  );

  if updated = src then
    raise exception 'feed following cand posts branch patch failed';
  end if;
  src := updated;

  updated := replace(
    src,
    $old_pp$
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
$old_pp$,
    $new_pp$
      select * from (
        select kind, id, author_id, created_at
        from (
          (
          select
            'profile_post'::text as kind,
            pp.id,
            pp.user_id as author_id,
            pp.created_at
          from public.profile_posts pp
          where v_scope = 'global'
            and v_include_posts
            and pp.user_id is distinct from v_uid
            and (v_guest or not (pp.user_id = any (v_block_peers)))
            and public._v1_feed_before_cursor(
              pp.created_at, 'profile_post', pp.id,
              v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
            )
            and (cardinality(v_following) = 0 or not (pp.user_id = any (v_following)))
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
          )
          union all
          select lat.kind, lat.id, lat.author_id, lat.created_at
          from unnest(
            case when v_scope = 'following' then v_following else '{}'::uuid[] end
          ) as fid
          cross join lateral (
            select
              'profile_post'::text as kind,
              pp.id,
              pp.user_id as author_id,
              pp.created_at
            from public.profile_posts pp
            where v_include_posts
              and pp.user_id = fid
              and pp.user_id is distinct from v_uid
              and (v_guest or not (pp.user_id = any (v_block_peers)))
              and public._v1_feed_before_cursor(
                pp.created_at, 'profile_post', pp.id,
                v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
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
          ) lat
        ) profile_post_merge
        order by created_at desc, id desc
        limit (v_limit + 1)
      ) posts_c
$new_pp$
  );

  if updated = src then
    raise exception 'feed following cand profile_posts branch patch failed';
  end if;
  src := updated;

  updated := replace(
    src,
    $old_ap$
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
$old_ap$,
    $new_ap$
      select * from (
        select kind, id, author_id, created_at
        from (
          (
          select
            'achievement_post'::text as kind,
            ap.id,
            ap.user_id as author_id,
            ap.created_at
          from public.achievement_posts ap
          join public.achievements a on a.id = ap.achievement_id
          where v_scope = 'global'
            and v_include_achievements
            and ap.user_id is distinct from v_uid
            and (v_guest or not (ap.user_id = any (v_block_peers)))
            and coalesce(a.is_public, true) = true
            and public._v1_feed_before_cursor(
              ap.created_at, 'achievement_post', ap.id,
              v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
            )
            and (cardinality(v_following) = 0 or not (ap.user_id = any (v_following)))
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
          )
          union all
          select lat.kind, lat.id, lat.author_id, lat.created_at
          from unnest(
            case when v_scope = 'following' then v_following else '{}'::uuid[] end
          ) as fid
          cross join lateral (
            select
              'achievement_post'::text as kind,
              ap.id,
              ap.user_id as author_id,
              ap.created_at
            from public.achievement_posts ap
            join public.achievements a on a.id = ap.achievement_id
            where v_include_achievements
              and ap.user_id = fid
              and ap.user_id is distinct from v_uid
              and (v_guest or not (ap.user_id = any (v_block_peers)))
              and coalesce(a.is_public, true) = true
              and public._v1_feed_before_cursor(
                ap.created_at, 'achievement_post', ap.id,
                v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
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
          ) lat
        ) achievement_post_merge
        order by created_at desc, id desc
        limit (v_limit + 1)
      ) ach_c
$new_ap$
  );

  if updated = src then
    raise exception 'feed following cand achievement_posts branch patch failed';
  end if;
  src := updated;

  updated := replace(
    src,
    $old_rl$
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
$old_rl$,
    $new_rl$
      select * from (
        select kind, id, author_id, created_at
        from (
          (
          select
            'reel'::text as kind,
            r.id,
            r.user_id as author_id,
            r.created_at
          from public.reels r
          where v_scope = 'global'
            and v_include_reels
            and r.user_id is distinct from v_uid
            and (v_guest or not (r.user_id = any (v_block_peers)))
            and public._v1_feed_before_cursor(
              r.created_at, 'reel', r.id,
              v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
            )
            and (cardinality(v_following) = 0 or not (r.user_id = any (v_following)))
            and (v_filter = 'reels' or r.trade_id is null)
            and (not v_guest or coalesce(r.visibility, 'public') = 'public')
          order by r.created_at desc, r.id desc
          limit (v_limit + 1)
          )
          union all
          select lat.kind, lat.id, lat.author_id, lat.created_at
          from unnest(
            case when v_scope = 'following' then v_following else '{}'::uuid[] end
          ) as fid
          cross join lateral (
            select
              'reel'::text as kind,
              r.id,
              r.user_id as author_id,
              r.created_at
            from public.reels r
            where v_include_reels
              and r.user_id = fid
              and r.user_id is distinct from v_uid
              and (v_guest or not (r.user_id = any (v_block_peers)))
              and public._v1_feed_before_cursor(
                r.created_at, 'reel', r.id,
                v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy
              )
              and (v_filter = 'reels' or r.trade_id is null)
              and (not v_guest or coalesce(r.visibility, 'public') = 'public')
            order by r.created_at desc, r.id desc
            limit (v_limit + 1)
          ) lat
        ) reel_merge
        order by created_at desc, id desc
        limit (v_limit + 1)
      ) reels_c
$new_rl$
  );

  if updated = src then
    raise exception 'feed following cand reels branch patch failed';
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
  'Backend V2 Feed bootstrap — Following cand uses per-followee lateral top-N; blocks via get_active_block_peer_ids.';
