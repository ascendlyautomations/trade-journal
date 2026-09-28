-- Create Trade Room: honor per-channel allow_members_chat in p_channels JSON.
-- Falls back to room-level p_members_can_message when a channel omits the flag.

create or replace function public.rpc_v1_create_trade_room(
  p_name text,
  p_description text default null,
  p_image_url text default null,
  p_show_on_profile boolean default true,
  p_is_private boolean default false,
  p_category text default null,
  p_discovery_tags text[] default '{}'::text[],
  p_join_policy text default 'open',
  p_rules text default null,
  p_members_can_message boolean default true,
  p_members_can_share_trades boolean default true,
  p_members_can_share_media boolean default true,
  p_channels jsonb default '[{"name":"general"}]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_username text;
  v_slug text;
  v_room public.rooms%rowtype;
  v_channel jsonb;
  v_channel_name text;
  v_position int := 0;
  v_seen_names text[] := '{}'::text[];
  v_tag_count int;
  v_join_policy text := lower(trim(coalesce(p_join_policy, 'open')));
  v_category text := nullif(lower(trim(coalesce(p_category, ''))), '');
  v_name text := trim(coalesce(p_name, ''));
  v_description text := nullif(trim(coalesce(p_description, '')), '');
  v_rules text := nullif(trim(coalesce(p_rules, '')), '');
  v_room_allow_chat boolean := coalesce(p_members_can_message, true);
  v_channel_allow_chat boolean;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_name = '' then
    raise exception 'room_name_required' using errcode = '22023';
  end if;

  if char_length(v_name) > 100 then
    raise exception 'room_name_too_long' using errcode = '22023';
  end if;

  if v_description is not null and char_length(v_description) > 500 then
    raise exception 'room_description_too_long' using errcode = '22023';
  end if;

  if v_rules is not null and char_length(v_rules) > 2000 then
    raise exception 'room_rules_too_long' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.rooms r where r.owner_user_id = v_uid
  ) then
    raise exception 'owned_room_exists' using errcode = '23505';
  end if;

  if v_join_policy not in ('open', 'approval') then
    v_join_policy := 'open';
  end if;

  if v_category is not null and v_category not in (
    'futures', 'options', 'stocks', 'crypto', 'forex',
    'prop_firms', 'day_trading', 'swing_trading', 'general'
  ) then
    v_category := null;
  end if;

  v_tag_count := coalesce(array_length(p_discovery_tags, 1), 0);
  if v_tag_count > 5 then
    raise exception 'too_many_discovery_tags' using errcode = '22023';
  end if;

  if jsonb_typeof(p_channels) <> 'array' or jsonb_array_length(p_channels) < 1 then
    raise exception 'channels_required' using errcode = '22023';
  end if;

  if jsonb_array_length(p_channels) > 5 then
    raise exception 'too_many_channels' using errcode = '22023';
  end if;

  for v_channel in select * from jsonb_array_elements(p_channels)
  loop
    v_channel_name := trim(coalesce(v_channel->>'name', ''));
    if v_channel_name = '' then
      raise exception 'channel_name_required' using errcode = '22023';
    end if;
    if char_length(v_channel_name) > 64 then
      raise exception 'channel_name_too_long' using errcode = '22023';
    end if;
    if lower(v_channel_name) = any(v_seen_names) then
      raise exception 'duplicate_channel_name' using errcode = '22023';
    end if;
    v_seen_names := array_append(v_seen_names, lower(v_channel_name));
  end loop;

  select p.username into v_username
  from public.profiles p
  where p.id = v_uid;

  v_slug := coalesce(nullif(trim(v_username), ''), 'user')
    || '-' || (extract(epoch from clock_timestamp()) * 1000)::bigint::text;

  insert into public.rooms (
    name,
    description,
    owner_user_id,
    slug,
    image_url,
    show_on_profile,
    is_private,
    category,
    discovery_tags,
    join_policy,
    rules,
    members_can_message,
    members_can_share_trades,
    members_can_share_media,
    room_kind
  )
  values (
    v_name,
    coalesce(v_description, 'Personal Trade Room'),
    v_uid,
    v_slug,
    nullif(trim(coalesce(p_image_url, '')), ''),
    coalesce(p_show_on_profile, true),
    coalesce(p_is_private, false),
    v_category,
    coalesce(p_discovery_tags, '{}'::text[]),
    v_join_policy,
    v_rules,
    coalesce(p_members_can_message, true),
    coalesce(p_members_can_share_trades, true),
    coalesce(p_members_can_share_media, true),
    'community'
  )
  returning * into v_room;

  v_position := 0;
  for v_channel in select * from jsonb_array_elements(p_channels)
  loop
    v_position := v_position + 1;
    v_channel_name := trim(v_channel->>'name');
    if v_channel ? 'allow_members_chat' then
      v_channel_allow_chat := coalesce((v_channel->>'allow_members_chat')::boolean, v_room_allow_chat);
    else
      v_channel_allow_chat := v_room_allow_chat;
    end if;
    insert into public.room_sections (room_id, name, position, allow_members_chat)
    values (v_room.id, v_channel_name, v_position, v_channel_allow_chat);
  end loop;

  insert into public.room_members (room_id, user_id, notification_enabled)
  values (v_room.id, v_uid, true);

  perform public.ensure_room_member_tags_defaults(v_room.id);

  return jsonb_build_object(
    'id', v_room.id,
    'name', v_room.name,
    'description', v_room.description,
    'slug', v_room.slug,
    'image_url', v_room.image_url,
    'owner_user_id', v_room.owner_user_id,
    'show_on_profile', coalesce(v_room.show_on_profile, true),
    'is_private', coalesce(v_room.is_private, false),
    'category', v_room.category,
    'discovery_tags', coalesce(to_jsonb(v_room.discovery_tags), '[]'::jsonb),
    'join_policy', v_room.join_policy,
    'rules', v_room.rules,
    'members_can_message', coalesce(v_room.members_can_message, true),
    'members_can_share_trades', coalesce(v_room.members_can_share_trades, true),
    'members_can_share_media', coalesce(v_room.members_can_share_media, true),
    'room_kind', coalesce(v_room.room_kind, 'community'),
    'member_count', 1
  );
end;
$$;

comment on function public.rpc_v1_create_trade_room is
  'Atomic community Trade Room creation — room, channels (per-channel allow_members_chat), owner membership, default member tags.';

revoke all on function public.rpc_v1_create_trade_room from public;
grant execute on function public.rpc_v1_create_trade_room to authenticated;
