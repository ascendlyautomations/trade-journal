-- Public trade rooms remain discoverable when the owner profile is private.
-- Room visibility (rooms.is_private, show_on_profile, join_policy) is unchanged.

do $patch$
declare
  fn record;
  src text;
  updated text;
  targets constant text[] := array[
    'popular_trade_rooms',
    'search_public_trade_rooms',
    'rpc_v1_trade_room_discovery',
    'rpc_v1_trade_rooms_home_bootstrap',
    'rpc_v1_search_trade_rooms'
  ];
begin
  for fn in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any(targets)
  loop
    select pg_get_functiondef(fn.oid) into src;
    updated := src;

    updated := replace(
      updated,
      $join1$on p.id = r.owner_user_id
      and coalesce(p.is_private, false) = false$join1$,
      $join1$on p.id = r.owner_user_id$join1$
    );

    updated := replace(
      updated,
      $join2$on p.id = r.owner_user_id
    and coalesce(p.is_private, false) = false$join2$,
      $join2$on p.id = r.owner_user_id$join2$
    );

    updated := replace(
      updated,
      $own1$and r.owner_user_id is not null
          and p.id is not null$own1$,
      $own1$and r.owner_user_id is not null$own1$
    );

    updated := replace(
      updated,
      $own2$and r.owner_user_id is not null
        and p.id is not null$own2$,
      $own2$and r.owner_user_id is not null$own2$
    );

    if updated <> src then
      execute updated;
    end if;
  end loop;
end;
$patch$;

comment on function public.popular_trade_rooms(int) is
  'Public discovery: profile-visible, non-private rooms; owner profile may be private.';

comment on function public.search_public_trade_rooms(text, int) is
  'Public discovery: profile-visible, non-private rooms matching name or slug; owner profile may be private.';