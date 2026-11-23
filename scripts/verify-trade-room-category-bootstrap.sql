-- Regression spot-check: server category filter on rpc_v1_trade_rooms_home_bootstrap.
-- Run against staging/production with SQL editor (service role / postgres).

with unfiltered as (
  select public.rpc_v1_trade_rooms_home_bootstrap(50, 'all', null, null, null) as payload
),
futures as (
  select public.rpc_v1_trade_rooms_home_bootstrap(50, 'all', null, null, 'futures') as payload
),
options as (
  select public.rpc_v1_trade_rooms_home_bootstrap(50, 'all', null, null, 'options') as payload
)
select
  jsonb_array_length(unfiltered.payload -> 'data' -> 'popular') as popular_unfiltered,
  jsonb_array_length(futures.payload -> 'data' -> 'popular') as popular_futures,
  jsonb_array_length(options.payload -> 'data' -> 'popular') as popular_options,
  (
    select count(*)
    from jsonb_array_elements(futures.payload -> 'data' -> 'popular') row
    where lower(coalesce(row ->> 'category', '')) <> 'futures'
  ) as futures_non_matching_categories,
  (
    select count(*)
    from jsonb_array_elements(options.payload -> 'data' -> 'popular') row
    where lower(coalesce(row ->> 'category', '')) <> 'options'
  ) as options_non_matching_categories
from unfiltered, futures, options;