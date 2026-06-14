-- Admin Beta Dashboard V1: read-only aggregate bundle (security definer + admin_users gate).

create or replace function public.admin_beta_dashboard_bundle()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  week7 timestamptz := timezone('utc', now()) - interval '7 days';
  beta_room_id uuid;
  recent jsonb;
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select r.id
  into beta_room_id
  from public.rooms r
  where lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
  limit 1;

  with activity as (
    select
      'bug_report'::text as kind,
      br.id::text as item_id,
      br.user_id,
      coalesce(nullif(trim(br.title), ''), 'Bug report') as summary,
      br.created_at
    from public.bug_reports br
    union all
    select
      'feature_request'::text,
      fr.id::text,
      fr.user_id,
      coalesce(nullif(trim(fr.title), ''), 'Feature request'),
      fr.created_at
    from public.feature_requests fr
    union all
    select
      'room_message'::text,
      rm.id::text,
      rm.user_id,
      left(coalesce(nullif(trim(rm.content), ''), 'Room message'), 120),
      rm.created_at
    from public.room_messages rm
    where beta_room_id is not null
      and rm.room_id = beta_room_id
    union all
    select
      'trade'::text,
      t.id::text,
      t.user_id,
      coalesce(nullif(trim(t.ticker), ''), 'Trade'),
      t.created_at
    from public.trades t
    inner join public.profiles p on p.id = t.user_id
    where coalesce(p.is_beta_tester, false) = true
  ),
  ranked as (
    select
      a.kind,
      a.item_id,
      a.user_id,
      a.summary,
      a.created_at,
      coalesce(pr.username, '') as username
    from activity a
    left join public.profiles pr on pr.id = a.user_id
    order by a.created_at desc
    limit 20
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'kind', r.kind,
        'id', r.item_id,
        'userId', r.user_id,
        'username', r.username,
        'summary', r.summary,
        'createdAt', r.created_at
      )
      order by r.created_at desc
    ),
    '[]'::jsonb
  )
  into recent
  from ranked r;

  return jsonb_build_object(
    'totalBetaTesters', (
      select count(*)::bigint
      from public.profiles p
      where coalesce(p.is_beta_tester, false) = true
    ),
    'activeBetaTesters7d', (
      select count(*)::bigint
      from (
        select distinct t.user_id
        from public.trades t
        inner join public.profiles p on p.id = t.user_id
        where coalesce(p.is_beta_tester, false) = true
          and t.created_at >= week7
        union
        select distinct pp.user_id
        from public.profile_posts pp
        inner join public.profiles p on p.id = pp.user_id
        where coalesce(p.is_beta_tester, false) = true
          and pp.created_at >= week7
        union
        select distinct rm.user_id
        from public.room_messages rm
        inner join public.profiles p on p.id = rm.user_id
        where coalesce(p.is_beta_tester, false) = true
          and rm.created_at >= week7
      ) active_users
    ),
    'tradesTotal', (
      select count(*)::bigint
      from public.trades t
      inner join public.profiles p on p.id = t.user_id
      where coalesce(p.is_beta_tester, false) = true
    ),
    'trades7d', (
      select count(*)::bigint
      from public.trades t
      inner join public.profiles p on p.id = t.user_id
      where coalesce(p.is_beta_tester, false) = true
        and t.created_at >= week7
    ),
    'postsTotal', (
      select count(*)::bigint
      from public.profile_posts pp
      inner join public.profiles p on p.id = pp.user_id
      where coalesce(p.is_beta_tester, false) = true
    ),
    'posts7d', (
      select count(*)::bigint
      from public.profile_posts pp
      inner join public.profiles p on p.id = pp.user_id
      where coalesce(p.is_beta_tester, false) = true
        and pp.created_at >= week7
    ),
    'betaRoomMembers', (
      select count(*)::bigint
      from public.room_members rm
      where beta_room_id is not null
        and rm.room_id = beta_room_id
    ),
    'betaRoomMessages', (
      select count(*)::bigint
      from public.room_messages msg
      where beta_room_id is not null
        and msg.room_id = beta_room_id
    ),
    'bugReportsTotal', (select count(*)::bigint from public.bug_reports),
    'bugReportsOpen', (
      select count(*)::bigint from public.bug_reports where status = 'open'
    ),
    'bugReportsResolved', (
      select count(*)::bigint from public.bug_reports where status = 'resolved'
    ),
    'featureRequestsTotal', (select count(*)::bigint from public.feature_requests),
    'featureRequestsOpen', (
      select count(*)::bigint from public.feature_requests where status = 'open'
    ),
    'featureRequestsPlanned', (
      select count(*)::bigint from public.feature_requests where status = 'planned'
    ),
    'featureRequestsCompleted', (
      select count(*)::bigint from public.feature_requests where status = 'completed'
    ),
    'recentActivity', coalesce(recent, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.admin_beta_dashboard_bundle() from public;
grant execute on function public.admin_beta_dashboard_bundle() to authenticated;

comment on function public.admin_beta_dashboard_bundle() is
  'Admin-only beta program metrics and recent activity feed for /admin/beta.';
