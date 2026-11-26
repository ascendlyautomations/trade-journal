-- Rotating feed read path. rpc_v1_feed_bootstrap is never modified here.
-- Installs rpc_v2 by cloning live v1 (case/format agnostic). Safe to rerun.

create or replace function public._feed_rotating_v2_install_from_v1()
returns void
language plpgsql
security invoker
set search_path = public
as $install$
declare
  src text;
  dst text;
  v_cand_start int;
  v_authors_start int;
  v_ranked_section text;
  v_v1_oid oid;
  v_v1_prosecdef boolean;
  v_v2_oid oid;
begin
  select p.oid, p.prosecdef, pg_get_functiondef(p.oid)
    into v_v1_oid, v_v1_prosecdef, src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_feed_bootstrap'
    and p.prokind = 'f'
    and p.pronargs = 4
  order by p.oid
  limit 1;

  if src is null or v_v1_oid is null then
    raise exception 'rpc_v1_feed_bootstrap (4-arg) was not found — apply prior feed migrations first';
  end if;

  if coalesce(v_v1_prosecdef, false) then
    raise exception 'rpc_v1_feed_bootstrap must be security invoker (prosecdef=false) before v2 clone';
  end if;

  select p.oid
    into v_v2_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v2_feed_bootstrap'
    and p.prokind = 'f'
    and p.pronargs = 7
    and coalesce(p.prosecdef, false) = false
  order by p.oid
  limit 1;

  if v_v2_oid is not null then
    return;
  end if;

  drop function if exists public.rpc_v2_feed_bootstrap(
    text, text, integer, text, text, timestamptz, text[]
  );
  drop function if exists public.rpc_v2_feed_bootstrap(
    text, text, integer, text, text, timestamptz, text
  );

  if position('v_block_peers uuid[]' in src) = 0 then
    raise exception 'rpc_v1_feed_bootstrap missing v_block_peers — apply block peer migration first';
  end if;

  dst := src;
  dst := regexp_replace(
    dst,
    'FUNCTION\s+public\.rpc_v1_feed_bootstrap',
    'FUNCTION public.rpc_v2_feed_bootstrap',
    'gi'
  );
  dst := regexp_replace(
    dst,
    'p_cursor\s+text\s+DEFAULT\s+NULL(::text)?\s*\)\s+RETURNS',
    'p_cursor text DEFAULT NULL::text, p_session_seed text DEFAULT NULL::text, p_rank_frozen_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_scan_cursor text DEFAULT NULL::text) RETURNS',
    'i'
  );

  if strpos(lower(dst), 'rpc_v2_feed_bootstrap') = 0 then
    raise exception 'v2 clone failed: target name not present in ddl (check FUNCTION rename)';
  end if;
  if dst ~* 'FUNCTION\s+public\.rpc_v1_feed_bootstrap' then
    raise exception 'v2 clone failed: v1 signature still present — aborting to protect rpc_v1_feed_bootstrap';
  end if;

  dst := replace(
    dst,
    '  v_cursor_legacy boolean := true;' || chr(10),
    '  v_cursor_legacy boolean := true;' || chr(10) ||
      '  v_rank_score double precision;' || chr(10) ||
      '  v_rank_kind text;' || chr(10) ||
      '  v_rank_id uuid;' || chr(10) ||
      '  v_rank_kind_rank integer;' || chr(10) ||
      '  v_pool integer;' || chr(10) ||
      '  v_frozen timestamptz;' || chr(10) ||
      '  v_seed text;' || chr(10)
  );

  dst := replace(
    dst,
    '  select c.cursor_ts, c.cursor_kind, c.cursor_id, c.cursor_kind_rank, c.legacy_only' || chr(10) ||
      '  into v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy' || chr(10) ||
      '  from public._v1_feed_parse_cursor(p_cursor) c;' || chr(10),
    '  select r.cursor_score, r.cursor_kind, r.cursor_id, r.cursor_kind_rank' || chr(10) ||
      '  into v_rank_score, v_rank_kind, v_rank_id, v_rank_kind_rank' || chr(10) ||
      '  from public._v2_feed_parse_rank_cursor(p_cursor) r;' || chr(10) || chr(10) ||
      '  select c.cursor_ts, c.cursor_kind, c.cursor_id, c.cursor_kind_rank, c.legacy_only' || chr(10) ||
      '  into v_cursor_ts, v_cursor_kind, v_cursor_id, v_cursor_kind_rank, v_cursor_legacy' || chr(10) ||
      '  from public._v1_feed_parse_cursor(p_scan_cursor) c;' || chr(10) || chr(10) ||
      '  v_pool := least(2000, greatest(v_limit * 16, 128));' || chr(10) ||
      '  v_frozen := coalesce(p_rank_frozen_at, timezone(''utc'', now()));' || chr(10) ||
      '  v_seed := coalesce(nullif(trim(p_session_seed), ''''), v_uid::text);' || chr(10)
  );

  v_cand_start := position('  cand as (' in dst);
  v_authors_start := position('  authors as (' in dst);
  if v_cand_start = 0 or v_authors_start = 0 or v_authors_start <= v_cand_start then
    raise exception 'rpc_v1_feed_bootstrap cand/authors anchors not found';
  end if;

  v_ranked_section := $v2$
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
              exists (select 1 from public.trades_public_read tx where tx.id = p.trade_id)
              and exists (
                select 1 from public.profiles pr
                where pr.id = p.user_id and coalesce(pr.is_private, false) = false
              )
            )
          )
        order by p.created_at desc, p.id desc
        limit (v_pool + 1)
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
        order by pp.created_at desc, pp.id desc
        limit (v_pool + 1)
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
        order by ap.created_at desc, ap.id desc
        limit (v_pool + 1)
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
        order by r.created_at desc, r.id desc
        limit (v_pool + 1)
      ) reels_c
    ) merged
  ),
  scan_floor as (
    select c.created_at, c.kind, c.id
    from cand c
    order by c.created_at asc, public._v1_feed_kind_rank(c.kind) asc, c.id asc
    limit 1
  ),
  scan_has_more as (
    select coalesce(
      (
        select exists (select 1 from cand limit 1)
        and (
          (
            v_include_trades
            and exists (
              select 1
              from public.posts p
              where p.user_id is distinct from v_uid
                and (v_guest or not (p.user_id = any (v_block_peers)))
                and public._v1_feed_before_cursor(
                  p.created_at, 'post', p.id,
                  sf.created_at, sf.kind, sf.id,
                  public._v1_feed_kind_rank(sf.kind), false
                )
                and (
                  (v_scope = 'following' and p.user_id = any (v_following))
                  or (v_scope = 'global' and (cardinality(v_following) = 0 or not (p.user_id = any (v_following))))
                )
              limit 1
            )
          )
          or (
            v_include_posts
            and exists (
              select 1
              from public.profile_posts pp
              where pp.user_id is distinct from v_uid
                and (v_guest or not (pp.user_id = any (v_block_peers)))
                and public._v1_feed_before_cursor(
                  pp.created_at, 'profile_post', pp.id,
                  sf.created_at, sf.kind, sf.id,
                  public._v1_feed_kind_rank(sf.kind), false
                )
                and (
                  (v_scope = 'following' and pp.user_id = any (v_following))
                  or (v_scope = 'global' and (cardinality(v_following) = 0 or not (pp.user_id = any (v_following))))
                )
              limit 1
            )
          )
          or (
            v_include_achievements
            and exists (
              select 1
              from public.achievement_posts ap
              join public.achievements a on a.id = ap.achievement_id
              where ap.user_id is distinct from v_uid
                and (v_guest or not (ap.user_id = any (v_block_peers)))
                and coalesce(a.is_public, true) = true
                and public._v1_feed_before_cursor(
                  ap.created_at, 'achievement_post', ap.id,
                  sf.created_at, sf.kind, sf.id,
                  public._v1_feed_kind_rank(sf.kind), false
                )
                and (
                  (v_scope = 'following' and ap.user_id = any (v_following))
                  or (v_scope = 'global' and (cardinality(v_following) = 0 or not (ap.user_id = any (v_following))))
                )
              limit 1
            )
          )
          or (
            v_include_reels
            and exists (
              select 1
              from public.reels r
              where r.user_id is distinct from v_uid
                and (v_guest or not (r.user_id = any (v_block_peers)))
                and public._v1_feed_before_cursor(
                  r.created_at, 'reel', r.id,
                  sf.created_at, sf.kind, sf.id,
                  public._v1_feed_kind_rank(sf.kind), false
                )
                and (
                  (v_scope = 'following' and r.user_id = any (v_following))
                  or (v_scope = 'global' and (cardinality(v_following) = 0 or not (r.user_id = any (v_following))))
                )
                and (v_filter = 'reels' or r.trade_id is null)
              limit 1
            )
          )
        )
        from scan_floor sf
      ),
      false
    ) as val
  ),
  pool as (
    select
      c.kind,
      c.id,
      c.author_id,
      c.created_at,
      fi.effective_impressed_at
    from cand c
    left join lateral (
      select public._v2_feed_effective_impressed_at(
        i.last_impressed_at, i.first_impressed_at, v_frozen
      ) as effective_impressed_at
      from public.feed_content_impressions i
      where i.viewer_id = v_uid
        and i.content_kind = c.kind
        and i.content_id = c.id
    ) fi on not coalesce(v_guest, false)
  ),
  scored as (
    select
      p.kind,
      p.id,
      p.author_id,
      p.created_at,
      public._v2_feed_score(
        p.kind, p.id, p.created_at, p.effective_impressed_at, v_frozen, v_seed
      ) as score
    from pool p
  ),
  ranked as (
    select
      row_number() over (
        order by s.score desc, public._v1_feed_kind_rank(s.kind) desc, s.id desc
      ) as rn,
      s.kind,
      s.id,
      s.author_id,
      s.created_at,
      s.score
    from scored s
    where public._v2_feed_before_rank_cursor(
      s.score, s.kind, s.id,
      v_rank_score, v_rank_kind, v_rank_id, v_rank_kind_rank
    )
  ),
  page as (
    select kind, id, author_id, created_at, rn, score
    from ranked
    where rn <= v_limit
    order by rn
  ),
  page_meta as (
    select
      (select count(*)::integer from page) as returned,
      (
        exists (select 1 from ranked where rn > v_limit)
        or (select val from scan_has_more)
      ) as has_more,
      (
        exists (select 1 from ranked where rn > v_limit)
      ) as rank_has_more,
      (select val from scan_has_more) as scan_has_more,
      (
        select jsonb_build_object(
          'kind', p.kind,
          'id', p.id,
          'created_at', p.created_at,
          'score', p.score
        )
        from page p
        order by p.rn desc
        limit 1
      ) as last_row
  ),
$v2$;

  dst := substring(dst from 1 for v_cand_start - 1)
    || v_ranked_section
    || substring(dst from v_authors_start);

  dst := replace(
    dst,
    $next_cur$
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
$next_cur$,
    $next_cur_v2$
      'next_cursor', case
        when (select rank_has_more from page_meta)
          and (select last_row from page_meta) is not null
          then (
            to_char(((select last_row from page_meta) ->> 'score')::double precision, 'FM999999999990.000000')
            || '|'
            || ((select last_row from page_meta) ->> 'kind')
            || '|'
            || ((select last_row from page_meta) ->> 'id')
          )
        when (select scan_has_more from page_meta)
          and exists (select 1 from scan_floor)
          then (
            to_char(timezone('utc', (select created_at from scan_floor)), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
            || '|'
            || (select kind from scan_floor)
            || '|'
            || (select id::text from scan_floor)
          )
        else null
      end,
$next_cur_v2$
  );

  dst := replace(
    dst,
    'comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is',
    'comment on function public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text) is'
  );
  dst := regexp_replace(
    dst,
    'revoke all on function public\.rpc_v1_feed_bootstrap\(text, text, integer, text\) from public;',
  'revoke all on function public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text) from public;',
    'g'
  );
  dst := regexp_replace(
    dst,
    'grant execute on function public\.rpc_v1_feed_bootstrap\(text, text, integer, text\) to (authenticated|anon);',
    'grant execute on function public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text) to \1;',
    'g'
  );

  if position('security definer' in lower(dst)) > 0 then
    raise exception 'rpc_v2_feed_bootstrap must not use security definer';
  end if;

  -- PostgreSQL omits SECURITY INVOKER in pg_get_functiondef when it is the default.
  if position('security invoker' in lower(dst)) = 0 then
    if position(E'\nSET search_path = public' in dst) > 0 then
      dst := replace(
        dst,
        E'\nSET search_path = public',
        E'\nSECURITY INVOKER\nSET search_path = public'
      );
    elsif position(E'\nSET search_path TO public' in dst) > 0 then
      dst := replace(
        dst,
        E'\nSET search_path TO public',
        E'\nSECURITY INVOKER\nSET search_path TO public'
      );
    elsif position(E'\nSET search_path TO ''public''' in dst) > 0 then
      dst := replace(
        dst,
        E'\nSET search_path TO ''public''',
        E'\nSECURITY INVOKER\nSET search_path TO ''public'''
      );
    else
      dst := regexp_replace(
        dst,
        '(LANGUAGE plpgsql\s*\n)',
        E'\\1SECURITY INVOKER\n',
        'i'
      );
    end if;
  end if;

  if position('security definer' in lower(dst)) > 0 then
    raise exception 'rpc_v2_feed_bootstrap must not use security definer after patch';
  end if;

  -- pg_get_functiondef returns a single CREATE OR REPLACE FUNCTION statement.
  execute dst;

  select p.oid
    into v_v2_oid
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v2_feed_bootstrap'
    and p.prokind = 'f'
    and p.pronargs = 7;

  if v_v2_oid is null then
    raise exception 'rpc_v2_feed_bootstrap was not created (expected 7-arg)';
  end if;

  if exists (
    select 1 from pg_proc p where p.oid = v_v2_oid and coalesce(p.prosecdef, false)
  ) then
    raise exception 'rpc_v2_feed_bootstrap must be security invoker (prosecdef=false)';
  end if;

  if not exists (
    select 1
    from pg_proc p
    where p.oid = v_v1_oid
      and p.proname = 'rpc_v1_feed_bootstrap'
      and p.pronargs = 4
      and coalesce(p.prosecdef, false) = false
  ) then
    raise exception 'rpc_v1_feed_bootstrap was altered — migration aborted post-check';
  end if;
end
$install$;

revoke all on function public._feed_rotating_v2_install_from_v1() from public;

select public._feed_rotating_v2_install_from_v1();

do $grant$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'rpc_v2_feed_bootstrap' and p.pronargs = 7) then
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      grant execute on function public.rpc_v2_feed_bootstrap(
        text, text, integer, text, text, timestamptz, text
      ) to authenticated;
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
      grant execute on function public.rpc_v2_feed_bootstrap(
        text, text, integer, text, text, timestamptz, text
      ) to anon;
    end if;
  end if;
end
$grant$;

do $comment$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v2_feed_bootstrap'
      and p.pronargs = 7
  ) then
    execute $cmd$
      comment on function public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text) is
        'Rotating feed bootstrap — rank + chrono scan cursors, frozen impression snapshot. v1 unchanged.'
    $cmd$;
  end if;
end
$comment$;