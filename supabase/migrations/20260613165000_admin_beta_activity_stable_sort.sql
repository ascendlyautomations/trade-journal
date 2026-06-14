-- Stabilize beta activity pagination: tie-break sort prevents offset overlap on equal timestamps.

create or replace function public.admin_beta_activity(
  p_limit int default 20,
  p_offset int default 0,
  p_search text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  lim int := greatest(1, least(coalesce(p_limit, 20), 100));
  off int := greatest(0, coalesce(p_offset, 0));
  q text := nullif(trim(coalesce(p_search, '')), '');
  beta_room_id uuid;
begin
  if uid is null or not exists (select 1 from public.admin_users au where au.user_id = uid) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  select r.id
  into beta_room_id
  from public.rooms r
  where lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
  limit 1;

  return coalesce((
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
    filtered as (
      select
        a.kind,
        a.item_id,
        a.user_id,
        a.summary,
        a.created_at,
        coalesce(pr.username, '') as username
      from activity a
      left join public.profiles pr on pr.id = a.user_id
      where
        q is null
        or coalesce(pr.username, '') ilike '%' || q || '%'
        or a.user_id::text ilike '%' || q || '%'
    )
    select jsonb_agg(
      jsonb_build_object(
        'kind', f.kind,
        'id', f.item_id,
        'userId', f.user_id,
        'username', f.username,
        'summary', f.summary,
        'createdAt', f.created_at
      )
      order by f.created_at desc, f.kind asc, f.item_id desc
    )
    from (
      select *
      from filtered f
      order by f.created_at desc, f.kind asc, f.item_id desc
      limit lim
      offset off
    ) f
  ), '[]'::jsonb);
end;
$$;
