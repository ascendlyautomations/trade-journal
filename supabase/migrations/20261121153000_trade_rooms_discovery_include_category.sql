-- Trade Rooms discovery payloads: include rooms.category for native category filtering.
-- Root cause: home bootstrap + discovery RPCs omitted category though create/setup persists it.

create or replace function public.rpc_v1_trade_rooms_home_bootstrap(
  p_limit int default 20,
  p_scope text default 'all',
  p_suggested_cursor text default null,
  p_popular_cursor text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_scope text := lower(trim(coalesce(p_scope, 'all')));
  v_match_slug text := public.trade_room_suggested_official_slug(v_uid);
  v_suggested_cur jsonb := public._trade_rooms_parse_discovery_cursor(p_suggested_cursor);
  v_popular_cur jsonb := public._trade_rooms_parse_discovery_cursor(p_popular_cursor);
  v_skip_your boolean := v_suggested_cur is not null or v_popular_cur is not null;
  v_your jsonb;
  v_suggested jsonb;
  v_popular jsonb;
  v_suggested_next text;
  v_popular_next text;
begin
  if v_scope not in ('all', 'official', 'community') then
    v_scope := 'all';
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
  recent_activity as (
    select
      rm.room_id,
      count(*)::int as recent_message_count
    from public.room_messages rm
    where rm.created_at > (timezone('utc', now()) - interval '7 days')
    group by rm.room_id
  ),
  base_eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      r.category,
      r.join_policy,
      r.owner_user_id,
      p.username as owner_username,
      p.name as owner_name,
      p.avatar_url as owner_avatar_url,
      vjr.status as viewer_join_request_status,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      coalesce(fc.followed_member_count, 0) as followed_member_count,
      coalesce(ra.recent_message_count, 0) as recent_message_count,
      (
        v_uid is not null
        and r.owner_user_id = v_uid
      ) as is_owner,
      (
        v_uid is not null
        and exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      ) as is_member,
      case
        when r.room_kind = 'official'
          and lower(trim(coalesce(r.slug, ''))) = coalesce(v_match_slug, '')
        then 1000
        else 0
      end as suggested_boost
    from public.rooms r
    left join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join followed_counts fc
      on fc.room_id = r.id
    left join recent_activity ra
      on ra.room_id = r.id
    left join public.room_join_requests vjr
      on vjr.room_id = r.id
      and vjr.user_id = v_uid
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        v_scope = 'all'
        or (v_scope = 'official' and r.room_kind = 'official')
        or (v_scope = 'community' and r.room_kind = 'community')
      )
      and (
        r.room_kind = 'official'
        or (
          r.room_kind = 'community'
          and r.owner_user_id is not null
          and p.id is not null
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
      r.room_kind,
      r.discovery_tags,
      r.category,
      r.join_policy,
      r.owner_user_id,
      p.username,
      p.name,
      p.avatar_url,
      vjr.status,
      fc.followed_member_count,
      ra.recent_message_count
  ),
  your_ranked as (
    select *
    from base_eligible
    where not v_skip_your
      and v_uid is not null
      and (
        is_owner
        or is_member
      )
    order by
      case when is_owner then 0 else 1 end,
      member_count desc,
      recent_message_count desc,
      name asc,
      id asc
    limit v_limit
  ),
  suggested_page as (
    select *
    from base_eligible
    where (
        v_uid is null
        or not is_member
      )
      and public._trade_rooms_suggested_after(
      suggested_boost,
      followed_member_count,
      member_count::int,
      recent_message_count,
      name,
      id,
      v_suggested_cur
    )
    order by
      suggested_boost desc,
      followed_member_count desc,
      member_count desc,
      recent_message_count desc,
      name asc,
      id asc
    limit v_limit + 1
  ),
  suggested_ranked as (
    select * from suggested_page
    order by
      suggested_boost desc,
      followed_member_count desc,
      member_count desc,
      recent_message_count desc,
      name asc,
      id asc
    limit v_limit
  ),
  popular_page as (
    select *
    from base_eligible
    where (
        v_uid is null
        or not is_member
      )
      and public._trade_rooms_popular_after(
      member_count::int,
      recent_message_count,
      name,
      id,
      v_popular_cur
    )
    order by
      member_count desc,
      recent_message_count desc,
      name asc,
      id asc
    limit v_limit + 1
  ),
  popular_ranked as (
    select * from popular_page
    order by
      member_count desc,
      recent_message_count desc,
      name asc,
      id asc
    limit v_limit
  ),
  suggested_meta as (
    select
      (select count(*) from suggested_page) > v_limit as has_more,
      (
        select jsonb_build_object(
          'sb', suggested_boost,
          'fc', followed_member_count,
          'mc', member_count,
          'ra', recent_message_count,
          'n', name,
          'id', id
        )::text
        from suggested_ranked
        order by
          suggested_boost desc,
          followed_member_count desc,
          member_count desc,
          recent_message_count desc,
          name asc,
          id asc
        offset v_limit - 1
        limit 1
      ) as next_cursor
  ),
  popular_meta as (
    select
      (select count(*) from popular_page) > v_limit as has_more,
      (
        select jsonb_build_object(
          'mc', member_count,
          'ra', recent_message_count,
          'n', name,
          'id', id
        )::text
        from popular_ranked
        order by
          member_count desc,
          recent_message_count desc,
          name asc,
          id asc
        offset v_limit - 1
        limit 1
      ) as next_cursor
  )
  select
    case when v_skip_your then '[]'::jsonb else coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'name', name,
            'description', description,
            'slug', slug,
            'member_count', member_count,
            'image_url', image_url,
            'room_kind', room_kind,
            'category', category,
            'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
            'join_policy', coalesce(join_policy, 'open'),
            'viewer_join_request_status', viewer_join_request_status,
            'followed_member_count', followed_member_count,
            'recent_message_count', recent_message_count,
            'is_owner', is_owner,
            'is_member', is_member,
            'owner', case
              when owner_user_id is null then null
              else jsonb_build_object(
                'id', owner_user_id,
                'username', owner_username,
                'name', owner_name,
                'avatar_url', owner_avatar_url
              )
            end
          )
          order by
            case when is_owner then 0 else 1 end,
            member_count desc,
            recent_message_count desc,
            name asc
        )
        from your_ranked
      ),
      '[]'::jsonb
    ) end,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'name', name,
            'description', description,
            'slug', slug,
            'member_count', member_count,
            'image_url', image_url,
            'room_kind', room_kind,
            'category', category,
            'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
            'join_policy', coalesce(join_policy, 'open'),
            'viewer_join_request_status', viewer_join_request_status,
            'followed_member_count', followed_member_count,
            'recent_message_count', recent_message_count,
            'is_owner', is_owner,
            'is_member', is_member,
            'owner', case
              when owner_user_id is null then null
              else jsonb_build_object(
                'id', owner_user_id,
                'username', owner_username,
                'name', owner_name,
                'avatar_url', owner_avatar_url
              )
            end
          )
          order by
            suggested_boost desc,
            followed_member_count desc,
            member_count desc,
            recent_message_count desc,
            name asc
        )
        from suggested_ranked
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', id,
            'name', name,
            'description', description,
            'slug', slug,
            'member_count', member_count,
            'image_url', image_url,
            'room_kind', room_kind,
            'category', category,
            'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
            'join_policy', coalesce(join_policy, 'open'),
            'viewer_join_request_status', viewer_join_request_status,
            'followed_member_count', followed_member_count,
            'recent_message_count', recent_message_count,
            'is_owner', is_owner,
            'is_member', is_member,
            'owner', case
              when owner_user_id is null then null
              else jsonb_build_object(
                'id', owner_user_id,
                'username', owner_username,
                'name', owner_name,
                'avatar_url', owner_avatar_url
              )
            end
          )
          order by
            member_count desc,
            recent_message_count desc,
            name asc
        )
        from popular_ranked
      ),
      '[]'::jsonb
    ),
    (select case when has_more then next_cursor else null end from suggested_meta),
    (select case when has_more then next_cursor else null end from popular_meta)
  into v_your, v_suggested, v_popular, v_suggested_next, v_popular_next;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'scope', v_scope,
      'your_rooms', coalesce(v_your, '[]'::jsonb),
      'suggested', coalesce(v_suggested, '[]'::jsonb),
      'popular', coalesce(v_popular, '[]'::jsonb),
      'suggested_next_cursor', v_suggested_next,
      'popular_next_cursor', v_popular_next
    )
  );
end;
$$;

comment on function public.rpc_v1_trade_rooms_home_bootstrap(int, text, text, text) is
  'Native Trade Rooms home — your_rooms + keyset-paginated suggested/popular discovery.';


comment on function public.rpc_v1_trade_rooms_home_bootstrap(int, text, text, text) is
  'Native Trade Rooms home — your_rooms + keyset-paginated suggested/popular discovery.';

grant execute on function public.rpc_v1_trade_rooms_home_bootstrap(int, text, text, text) to authenticated, anon;

create or replace function public.rpc_v1_trade_room_discovery(
  p_mode text default 'popular',
  p_limit int default 20,
  p_scope text default 'all'
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
  v_scope text := lower(trim(coalesce(p_scope, 'all')));
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_match_slug text := public.trade_room_suggested_official_slug(v_uid);
  v_rooms jsonb := '[]'::jsonb;
begin
  if v_mode not in ('popular', 'suggested', 'your_rooms') then
    v_mode := 'popular';
  end if;
  if v_scope not in ('all', 'official', 'community') then
    v_scope := 'all';
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
  recent_activity as (
    select
      rm.room_id,
      count(*)::int as recent_message_count
    from public.room_messages rm
    where rm.created_at > (timezone('utc', now()) - interval '7 days')
    group by rm.room_id
  ),
  eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      r.category,
      r.join_policy,
      r.owner_user_id,
      p.username as owner_username,
      p.name as owner_name,
      p.avatar_url as owner_avatar_url,
      vjr.status as viewer_join_request_status,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      coalesce(fc.followed_member_count, 0) as followed_member_count,
      coalesce(ra.recent_message_count, 0) as recent_message_count,
      (
        v_uid is not null
        and r.owner_user_id = v_uid
      ) as is_owner,
      (
        v_uid is not null
        and exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      ) as is_member,
      case
        when v_mode = 'suggested'
          and r.room_kind = 'official'
          and lower(trim(coalesce(r.slug, ''))) = coalesce(v_match_slug, '')
        then 1000
        else 0
      end as suggested_boost
    from public.rooms r
    left join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join followed_counts fc
      on fc.room_id = r.id
    left join recent_activity ra
      on ra.room_id = r.id
    left join public.room_join_requests vjr
      on vjr.room_id = r.id
      and vjr.user_id = v_uid
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        v_scope = 'all'
        or (v_scope = 'official' and r.room_kind = 'official')
        or (v_scope = 'community' and r.room_kind = 'community')
      )
      and (
        r.room_kind = 'official'
        or (
          r.room_kind = 'community'
          and r.owner_user_id is not null
          and p.id is not null
        )
      )
      and (
        v_mode = 'your_rooms'
        and v_uid is not null
        and (
          r.owner_user_id = v_uid
          or exists (
            select 1
            from public.room_members vm
            where vm.room_id = r.id
              and vm.user_id = v_uid
              and vm.left_at is null
          )
        )
        or (
          v_mode <> 'your_rooms'
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
      r.room_kind,
      r.discovery_tags,
      r.category,
      r.join_policy,
      r.owner_user_id,
      p.username,
      p.name,
      p.avatar_url,
      vjr.status,
      fc.followed_member_count,
      ra.recent_message_count
  ),
  ranked as (
    select *
    from eligible
    order by
      case when v_mode = 'your_rooms' and is_owner then 0 else 1 end,
      case when v_mode = 'suggested' then suggested_boost else 0 end desc,
      case when v_mode = 'suggested' then followed_member_count else 0 end desc,
      member_count desc,
      recent_message_count desc,
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
        'room_kind', room_kind,
        'category', category,
        'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
        'join_policy', coalesce(join_policy, 'open'),
        'viewer_join_request_status', viewer_join_request_status,
        'followed_member_count', followed_member_count,
        'recent_message_count', recent_message_count,
        'is_owner', is_owner,
        'is_member', is_member,
        'owner', case
          when owner_user_id is null then null
          else jsonb_build_object(
            'id', owner_user_id,
            'username', owner_username,
            'name', owner_name,
            'avatar_url', owner_avatar_url
          )
        end
      )
      order by
        case when v_mode = 'your_rooms' and is_owner then 0 else 1 end,
        case when v_mode = 'suggested' then suggested_boost else 0 end desc,
        case when v_mode = 'suggested' then followed_member_count else 0 end desc,
        member_count desc,
        recent_message_count desc,
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
      'scope', v_scope,
      'rooms', v_rooms
    )
  );
end;
$$;

comment on function public.rpc_v1_trade_room_discovery(text, int, text) is
  'Native Trade Rooms discovery — popular, suggested, your_rooms. Includes authoritative is_owner/is_member for viewer.';


comment on function public.rpc_v1_trade_room_discovery(text, int, text) is
  'Native Trade Rooms discovery — popular, suggested, your_rooms. Includes authoritative is_owner/is_member for viewer.';

grant execute on function public.rpc_v1_trade_room_discovery(text, int, text) to authenticated, anon;

create or replace function public.rpc_v1_search_trade_rooms(
  p_query text,
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
  v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_term text := trim(coalesce(p_query, ''));
  v_rooms jsonb := '[]'::jsonb;
begin
  if v_term = '' then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 'v1'),
      'data', jsonb_build_object('rooms', '[]'::jsonb)
    );
  end if;

  with eligible as (
    select
      r.id,
      r.name,
      r.description,
      r.slug,
      r.image_url,
      r.room_kind,
      r.discovery_tags,
      r.category,
      coalesce(r.join_policy, 'open') as join_policy,
      vjr.status as viewer_join_request_status,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      (
        v_uid is not null
        and exists (
          select 1
          from public.room_members vm
          where vm.room_id = r.id
            and vm.user_id = v_uid
            and vm.left_at is null
        )
      ) as is_member
    from public.rooms r
    left join public.profiles p
      on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false
    left join public.room_members m
      on m.room_id = r.id
    left join public.room_join_requests vjr
      on vjr.room_id = r.id
      and vjr.user_id = v_uid
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        coalesce(r.room_kind, 'community') = 'official'
        or (
          coalesce(r.room_kind, 'community') = 'community'
          and r.owner_user_id is not null
          and p.id is not null
        )
      )
      and (
        r.name ilike '%' || v_term || '%'
        or r.slug ilike '%' || v_term || '%'
        or coalesce(r.description, '') ilike '%' || v_term || '%'
        or exists (
          select 1
          from unnest(coalesce(r.discovery_tags, '{}'::text[])) tag
          where tag ilike '%' || v_term || '%'
        )
      )
    group by
      r.id, r.name, r.description, r.slug, r.image_url, r.room_kind,
      r.discovery_tags, r.category, r.join_policy, vjr.status
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
        'room_kind', room_kind,
        'category', category,
        'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
        'join_policy', join_policy,
        'viewer_join_request_status', viewer_join_request_status,
        'is_member', is_member
      )
      order by
        case when coalesce(room_kind, 'community') = 'official' then 0 else 1 end,
        member_count desc,
        name asc
    ),
    '[]'::jsonb
  )
  into v_rooms
  from (
    select * from eligible
    order by
      case when coalesce(room_kind, 'community') = 'official' then 0 else 1 end,
      member_count desc,
      name asc
    limit v_limit
  ) ranked;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_jsonb(timezone('utc', now())),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object('rooms', v_rooms)
  );
end;
$$;

comment on function public.rpc_v1_search_trade_rooms(text, int) is
  'Rich Trade Room search for native/shared clients. Web continues using search_public_trade_rooms.';


comment on function public.rpc_v1_search_trade_rooms(text, int) is
  'Rich Trade Room search for native/shared clients. Web continues using search_public_trade_rooms.';

grant execute on function public.rpc_v1_search_trade_rooms(text, int) to authenticated, anon;
