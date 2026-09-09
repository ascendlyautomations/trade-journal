-- Official vs Community Trade Rooms — authoritative room_kind, idempotent seeds,
-- discovery/search RPC updates, and guards so users cannot create or mutate official rooms.

-- =============================================================================
-- 1. Schema
-- =============================================================================

alter table public.rooms
  add column if not exists room_kind text not null default 'community';

alter table public.rooms
  add column if not exists discovery_tags text[] not null default '{}'::text[];

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'rooms_room_kind_check'
      and conrelid = 'public.rooms'::regclass
  ) then
    alter table public.rooms
      add constraint rooms_room_kind_check
      check (room_kind in ('community', 'official'));
  end if;
end $$;

comment on column public.rooms.room_kind is
  'community = user-owned Trade Room; official = TradeTraxs-managed global community. Only service role may set official.';

comment on column public.rooms.discovery_tags is
  'Optional discovery/search labels for official rooms (and future curated community rooms).';

-- =============================================================================
-- 2. Guards — users cannot create, reclassify, or mutate official rooms
-- =============================================================================

create or replace function public.rooms_room_kind_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if coalesce(new.room_kind, 'community') <> 'community' then
      raise exception 'official rooms cannot be created by users'
        using errcode = '42501';
    end if;
    new.room_kind := 'community';
    new.discovery_tags := coalesce(new.discovery_tags, '{}'::text[]);
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if old.room_kind = 'official' then
      if not public.rate_limit_is_service_role() then
        raise exception 'official rooms are managed by TradeTraxs'
          using errcode = '42501';
      end if;
    elsif new.room_kind is distinct from old.room_kind then
      raise exception 'room_kind cannot be changed'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if tg_op = 'DELETE' and old.room_kind = 'official' then
    if not public.rate_limit_is_service_role() then
      raise exception 'official rooms cannot be deleted'
        using errcode = '42501';
    end if;
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists rooms_room_kind_guard on public.rooms;
create trigger rooms_room_kind_guard
  before insert or update or delete on public.rooms
  for each row
  execute function public.rooms_room_kind_guard();

-- Official rooms are readable for discovery/preview (membership still required for messages).
drop policy if exists "rooms_select_official_discoverable" on public.rooms;
create policy "rooms_select_official_discoverable"
  on public.rooms
  for select
  to anon, authenticated
  using (
    room_kind = 'official'
    and coalesce(is_private, false) = false
    and coalesce(show_on_profile, true) = true
    and lower(trim(coalesce(slug, ''))) <> 'tradetraxs-beta'
  );

-- =============================================================================
-- 3. Idempotent Official Room seeds (slug-authoritative; safe to rerun)
-- =============================================================================

alter table public.rooms disable trigger rooms_room_kind_guard;

insert into public.rooms (
  name,
  description,
  slug,
  owner_user_id,
  show_on_profile,
  is_private,
  allow_members_chat,
  room_kind,
  discovery_tags
)
select
  v.name,
  v.description,
  v.slug,
  null,
  true,
  false,
  true,
  'official',
  v.discovery_tags
from (
  values
    (
      'Futures Traders',
      'Global community for futures traders sharing setups, risk management, and session review.',
      'futures-traders',
      array['Futures', 'Indices', 'Commodities']::text[]
    ),
    (
      'Options Traders',
      'Discuss options strategies, greeks, earnings plays, and risk management with traders worldwide.',
      'options-traders',
      array['Options', 'Derivatives']::text[]
    ),
    (
      'Stock Traders',
      'Community for stock traders — equities, swing holds, and intraday setups.',
      'stock-traders',
      array['Stocks', 'Equities', 'Investing']::text[]
    ),
    (
      'Crypto Traders',
      'Trade ideas and discussion for crypto markets — spot, perps, and on-chain context.',
      'crypto-traders',
      array['Crypto', 'Digital Assets']::text[]
    ),
    (
      'Forex Traders',
      'Forex-focused community for pairs, sessions, and macro-driven FX discussion.',
      'forex-traders',
      array['Forex', 'FX', 'Currencies']::text[]
    )
) as v(name, description, slug, discovery_tags)
where not exists (
  select 1
  from public.rooms r
  where lower(trim(coalesce(r.slug, ''))) = v.slug
     or (
       r.room_kind = 'official'
       and lower(trim(r.name)) = lower(trim(v.name))
     )
);

-- Re-enable guard after authoritative seeds.
alter table public.rooms enable trigger rooms_room_kind_guard;

insert into public.room_sections (room_id, name, position)
select r.id, 'general', 1
from public.rooms r
where r.room_kind = 'official'
  and lower(trim(coalesce(r.slug, ''))) in (
    'futures-traders',
    'options-traders',
    'stock-traders',
    'crypto-traders',
    'forex-traders'
  )
  and not exists (
    select 1
    from public.room_sections s
    where s.room_id = r.id
      and lower(trim(s.name)) = 'general'
  );

-- =============================================================================
-- 4. Helper — suggested official slug match from viewer profile
-- =============================================================================

create or replace function public.trade_room_suggested_official_slug(p_user_id uuid)
returns text
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_trader_type text;
  v_primary_market text;
  v_trading_style text;
  v_blob text;
  v_slug text := null;
begin
  if p_user_id is null then
    return null;
  end if;

  select
    lower(trim(coalesce(p.trader_type, ''))),
    lower(trim(coalesce(p.primary_market, ''))),
    lower(trim(coalesce(p.trading_style, '')))
  into v_trader_type, v_primary_market, v_trading_style
  from public.profiles p
  where p.id = p_user_id;

  v_slug := case v_trader_type
    when 'futures' then 'futures-traders'
    when 'options' then 'options-traders'
    when 'investor' then 'stock-traders'
    else null
  end;

  v_blob := v_trader_type || ' ' || v_primary_market || ' ' || v_trading_style;

  if v_blob ~ '(crypto|bitcoin|btc|eth|digital asset)' then
    if v_slug is null or v_trader_type not in ('futures', 'options') then
      v_slug := 'crypto-traders';
    end if;
  elsif v_blob ~ '(forex|\bfx\b|currency pair|currencies)' then
    if v_slug is null then
      v_slug := 'forex-traders';
    end if;
  elsif v_blob ~ '(prop firm|prop-firm|funded trader|funded account)' then
    v_slug := 'prop-firm-traders';
  elsif v_blob ~ '(day trad|scalp|intraday)' and v_slug is null then
    v_slug := 'futures-traders';
  elsif v_blob ~ 'swing' and v_slug is null then
    v_slug := 'stock-traders';
  elsif v_blob ~ 'beginner|new trader' and v_slug is null then
    v_slug := 'stock-traders';
  end if;

  return v_slug;
end;
$$;

comment on function public.trade_room_suggested_official_slug(uuid) is
  'Maps viewer profile fields to an official Trade Room slug for Suggested ranking boost (not access control).';

revoke all on function public.trade_room_suggested_official_slug(uuid) from public;
grant execute on function public.trade_room_suggested_official_slug(uuid) to authenticated, anon;

-- =============================================================================
-- 5. Discovery RPC — mode (suggested/popular), scope (all/official/community)
-- =============================================================================

drop function if exists public.rpc_v1_trade_room_discovery(text, int);

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
  if v_mode not in ('popular', 'suggested') then
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
      r.owner_user_id,
      p.username as owner_username,
      p.name as owner_name,
      p.avatar_url as owner_avatar_url,
      count(m.user_id) filter (where m.left_at is null) as member_count,
      coalesce(fc.followed_member_count, 0) as followed_member_count,
      coalesce(ra.recent_message_count, 0) as recent_message_count,
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
    where lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
      and coalesce(r.show_on_profile, true) = true
      and coalesce(r.is_private, false) = false
      and (
        v_scope = 'all'
        or (v_scope = 'official' and r.room_kind = 'official')
        or (v_scope = 'community' and r.room_kind = 'community')
      )
      and (
        (
          r.room_kind = 'official'
        )
        or (
          r.room_kind = 'community'
          and r.owner_user_id is not null
          and p.id is not null
        )
      )
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
      r.room_kind,
      r.discovery_tags,
      r.owner_user_id,
      p.username,
      p.name,
      p.avatar_url,
      fc.followed_member_count,
      ra.recent_message_count
  ),
  ranked as (
    select *
    from eligible
    order by
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
        'discovery_tags', coalesce(to_jsonb(discovery_tags), '[]'::jsonb),
        'followed_member_count', followed_member_count,
        'recent_message_count', recent_message_count,
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
  'Trade Room discovery — popular/suggested with all/official/community scope. Official rooms included without owner profile. Suggested boosts trader-matched official slug.';

grant execute on function public.rpc_v1_trade_room_discovery(text, int, text) to authenticated, anon;

-- =============================================================================
-- 6. Popular + search RPCs — web-compatible contracts, official-room discovery logic
-- =============================================================================
-- PRESERVE legacy RETURNS TABLE shapes used by web (`lib/popularTradeRooms.ts`,
-- `database.types.ts`). Official/community filtering lives in the query only.
-- Native rich discovery uses `rpc_v1_trade_room_discovery` instead.

create or replace function public.popular_trade_rooms(p_limit int default 12)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.slug,
    count(m.user_id) filter (where m.left_at is null) as member_count
  from public.rooms r
  left join public.profiles p
    on p.id = r.owner_user_id
    and coalesce(p.is_private, false) = false
  left join public.room_members m
    on m.room_id = r.id
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
  group by r.id, r.name, r.description, r.slug
  order by member_count desc, r.name asc
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;

create or replace function public.search_public_trade_rooms(
  p_query text,
  p_limit int default 20
)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint,
  image_url text
)
language sql
stable
security definer
set search_path = public
as $$
  with q as (
    select trim(coalesce(p_query, '')) as term
  )
  select
    r.id,
    r.name,
    r.description,
    r.slug,
    count(m.user_id) filter (where m.left_at is null) as member_count,
    r.image_url
  from public.rooms r
  cross join q
  left join public.profiles p
    on p.id = r.owner_user_id
    and coalesce(p.is_private, false) = false
  left join public.room_members m
    on m.room_id = r.id
  where q.term <> ''
    and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
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
      r.name ilike '%' || q.term || '%'
      or r.slug ilike '%' || q.term || '%'
      or coalesce(r.description, '') ilike '%' || q.term || '%'
      or exists (
        select 1
        from unnest(coalesce(r.discovery_tags, '{}'::text[])) tag
        where tag ilike '%' || q.term || '%'
      )
    )
  group by r.id, r.name, r.description, r.slug, r.image_url
  order by
    case when coalesce(r.room_kind, 'community') = 'official' then 0 else 1 end,
    member_count desc,
    r.name asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

comment on function public.popular_trade_rooms(int) is
  'Public discovery: official and community profile-visible rooms; excludes tradetraxs-beta. Web-stable 5-column contract.';

comment on function public.search_public_trade_rooms(text, int) is
  'Public discovery search by name, slug, description, or discovery_tags. Web-stable 6-column contract.';

grant execute on function public.popular_trade_rooms(int) to authenticated, anon;
grant execute on function public.search_public_trade_rooms(text, int) to authenticated, anon;
