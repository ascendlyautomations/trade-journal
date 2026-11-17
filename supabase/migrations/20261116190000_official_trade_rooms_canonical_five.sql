-- Canonical Official Trade Rooms — exactly five UUIDs; demote any other official rows.
-- Keeps rpc_v1_trade_rooms_home_bootstrap p_scope = 'official' aligned with product.

alter table public.rooms disable trigger rooms_room_kind_guard;

update public.rooms
set room_kind = 'community'
where room_kind = 'official'
  and id not in (
    '3bf2ebcd-f189-4bd8-930c-51d61349f790'::uuid, -- Futures Traders
    '9d38241f-6ac5-4781-9468-d6d252417778'::uuid, -- Options Traders (slug options-traders)
    'a30b54d3-0922-43be-899d-9bce176a0256'::uuid, -- Stock Traders
    'd3eb7ffb-7233-42d1-b13c-9da9a9344700'::uuid, -- Crypto Traders
    'dd24cc33-421a-4b6e-b449-a3d3608399b3'::uuid  -- Forex Traders
  );

update public.rooms
set room_kind = 'official'
where id in (
  '3bf2ebcd-f189-4bd8-930c-51d61349f790'::uuid,
  '9d38241f-6ac5-4781-9468-d6d252417778'::uuid,
  'a30b54d3-0922-43be-899d-9bce176a0256'::uuid,
  'd3eb7ffb-7233-42d1-b13c-9da9a9344700'::uuid,
  'dd24cc33-421a-4b6e-b449-a3d3608399b3'::uuid
);

alter table public.rooms enable trigger rooms_room_kind_guard;