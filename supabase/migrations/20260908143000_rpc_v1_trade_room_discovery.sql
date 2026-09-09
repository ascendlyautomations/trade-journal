-- Trade Room discovery — single RPC for Suggested / Popular with full card payload.

create or replace function public.rpc_v1_trade_room_discovery(
  p_mode text default 'popular',
  p_limit int default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_mode text := lower(trim(coalesce(p_mode, 'popular')));
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_rooms jsonb := '[]'::jsonb;
begin
  if v_mode not in ('popular', 'suggested') then
    v_mode := 'popular';
  end if;

  with followed_counts as (
    select
      rm.room_id,
      count(distinct rm.user_id)::int as followed_member_count
    from public.room_members rm
    inner join public.followers f
      on f.following_id = rm.user_id
      and f.follower_id = v_uid
    where rm.left_at is null
      and v_uid is not null
    group by rm.room_id
  ),
  eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.owner_user_id,
      p.username as owner_username,
      p.name as owner_name,
      p.avatar_url as owner_avatar_url,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      coalesce(fc.followed_member_count, 0) as followed_member_count
    from public.rooms r
    inner join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join followed_counts fc
      on fc.room_id = r.id
    where r.owner_user_id is not null
      and coalesce(r.show_on_profile, true) = true
      and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and (
        v_uid is null
        or not exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      )
      and (
        v_uid is null
        or not public.is_room_banned(r.id, v_uid)
      )
    group by
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.owner_user_id,
      p.username,
      p.name,
      p.avatar_url,
      fc.followed_member_count
  ),
  ranked as (
    select *
    from eligible
    order by
      case when v_mode = 'suggested' then followed_member_count else 0 end desc,
      member_count desc,
      name asc
    limit v_limit
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'name', name,
        'description', description,
        'slug', slug,
        'member_count', member_count,
        'image_url', image_url,
        'followed_member_count', followed_member_count,
        'owner', jsonb_build_object(
          'id', owner_user_id,
          'username', owner_username,
          'name', owner_name,
          'avatar_url', owner_avatar_url
        )
      )
      order by
        case when v_mode = 'suggested' then followed_member_count else 0 end desc,
        member_count desc,
        name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from ranked;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'mode', v_mode,
      'rooms', v_rooms
    )
  );
end;
$$;

comment on function public.rpc_v1_trade_room_discovery(text, int) is
  'Public Trade Room discovery — popular (member count) or suggested (followed members in room, then member count). Excludes joined/banned rooms.';

grant execute on function public.rpc_v1_trade_room_discovery(text, int) to authenticated, anon;
