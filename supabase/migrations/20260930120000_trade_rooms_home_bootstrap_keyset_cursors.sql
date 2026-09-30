-- Trade Rooms home bootstrap — keyset pagination for suggested + popular discovery lists.

create or replace function public._trade_rooms_suggested_after(
  p_sb int,
  p_fc int,
  p_mc int,
  p_ra int,
  p_name text,
  p_id uuid,
  p_cursor jsonb
)
returns boolean
language sql
immutable
as $$
  select
    p_cursor is null
    or (
      p_sb < coalesce((p_cursor->>'sb')::int, 0)
      or (
        p_sb = coalesce((p_cursor->>'sb')::int, 0)
        and (
          p_fc < coalesce((p_cursor->>'fc')::int, 0)
          or (
            p_fc = coalesce((p_cursor->>'fc')::int, 0)
            and (
              p_mc < coalesce((p_cursor->>'mc')::int, 0)
              or (
                p_mc = coalesce((p_cursor->>'mc')::int, 0)
                and (
                  p_ra < coalesce((p_cursor->>'ra')::int, 0)
                  or (
                    p_ra = coalesce((p_cursor->>'ra')::int, 0)
                    and (
                      p_name > coalesce(p_cursor->>'n', '')
                      or (
                        p_name = coalesce(p_cursor->>'n', '')
                        and p_id > coalesce((p_cursor->>'id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    );
$$;

create or replace function public._trade_rooms_popular_after(
  p_mc int,
  p_ra int,
  p_name text,
  p_id uuid,
  p_cursor jsonb
)
returns boolean
language sql
immutable
as $$
  select
    p_cursor is null
    or (
      p_mc < coalesce((p_cursor->>'mc')::int, 0)
      or (
        p_mc = coalesce((p_cursor->>'mc')::int, 0)
        and (
          p_ra < coalesce((p_cursor->>'ra')::int, 0)
          or (
            p_ra = coalesce((p_cursor->>'ra')::int, 0)
            and (
              p_name > coalesce(p_cursor->>'n', '')
              or (
                p_name = coalesce(p_cursor->>'n', '')
                and p_id > coalesce((p_cursor->>'id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
              )
            )
          )
        )
      )
    );
$$;

create or replace function public._trade_rooms_parse_discovery_cursor(p_cursor text)
returns jsonb
language sql
immutable
as $$
  select case
    when p_cursor is null or btrim(p_cursor) = '' then null
    else p_cursor::jsonb
  end;
$$;

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

grant execute on function public.rpc_v1_trade_rooms_home_bootstrap(int, text, text, text) to authenticated, anon;

drop function if exists public.rpc_v1_trade_rooms_home_bootstrap(int, text);
