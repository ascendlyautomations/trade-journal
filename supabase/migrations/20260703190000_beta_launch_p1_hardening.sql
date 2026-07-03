-- Beta launch P1 hardening: leaderboard privacy, production rate limits, storage scoping.

-- ---------------------------------------------------------------------------
-- FIX #1 — Leaderboard: only public trades from public-profile users
-- ---------------------------------------------------------------------------
create or replace function public.leaderboard_trade_rows(
  p_offset int default 0,
  p_limit int default 1000
)
returns table (
  user_id uuid,
  pnl numeric,
  rr numeric,
  created_at timestamptz,
  account_type text,
  mode text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    t.user_id,
    t.pnl,
    t.rr,
    t.created_at,
    t.account_type::text,
    t.mode::text
  from public.trades t
  inner join public.profiles p on p.id = t.user_id
  where coalesce(p.is_private, false) = false
    and coalesce(t.is_public, false) = true
  order by t.created_at asc
  offset greatest(p_offset, 0)
  limit greatest(least(p_limit, 1000), 1);
$$;

comment on function public.leaderboard_trade_rows(int, int) is
  'Paginated minimal trade rows for leaderboard aggregation (public profiles + public trades only).';

-- ---------------------------------------------------------------------------
-- FIX #2 — Production rate limits (replace shadow-mode values)
-- ---------------------------------------------------------------------------
insert into public.rate_limit_rules (action, window_seconds, max_count)
values
  -- Messages / trade room messages: 60/min + reasonable hourly/daily caps
  ('message_send', 60, 60),
  ('message_send', 3600, 500),
  ('message_send', 86400, 2000),
  ('room_message', 60, 60),
  ('room_message', 3600, 500),
  ('room_message', 86400, 2000),
  -- Comments: 30/min
  ('comment', 60, 30),
  ('comment', 3600, 200),
  ('comment', 86400, 500),
  -- Likes / follows: moderate production defaults (no explicit beta spec)
  ('like', 60, 60),
  ('like', 3600, 300),
  ('like', 86400, 1000),
  ('follow', 3600, 30),
  ('follow', 86400, 200),
  -- User reviews: 5/day
  ('user_review', 86400, 5),
  -- Affiliate applications: 3/week
  ('affiliate_application', 604800, 3),
  -- CSV support submissions + client-side import gate: 10/hour
  ('csv_upload', 3600, 10),
  ('csv_import', 3600, 10)
on conflict (action, window_seconds) do update
  set max_count = excluded.max_count;

-- User reviews
create or replace function public.rate_limit_user_reviews_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('user_review');
  return NEW;
end;
$$;

drop trigger if exists rate_limit_user_reviews_before_insert on public.user_reviews;
create trigger rate_limit_user_reviews_before_insert
  before insert on public.user_reviews
  for each row
  execute function public.rate_limit_user_reviews_before_insert();

-- Affiliate applications
create or replace function public.rate_limit_affiliate_applications_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('affiliate_application');
  return NEW;
end;
$$;

drop trigger if exists rate_limit_affiliate_applications_before_insert on public.affiliate_applications;
create trigger rate_limit_affiliate_applications_before_insert
  before insert on public.affiliate_applications
  for each row
  execute function public.rate_limit_affiliate_applications_before_insert();

-- CSV support request submissions
create or replace function public.rate_limit_csv_support_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return NEW;
  end if;

  perform public.rate_limit_hit('csv_upload');
  return NEW;
end;
$$;

drop trigger if exists rate_limit_csv_support_before_insert on public.csv_support_requests;
create trigger rate_limit_csv_support_before_insert
  before insert on public.csv_support_requests
  for each row
  execute function public.rate_limit_csv_support_before_insert();

-- Whitelisted client-callable rate limit consumer (CSV import panel only)
create or replace function public.consume_app_rate_limit(p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_action is null or p_action not in ('csv_import') then
    raise exception 'rate_limit_invalid_action'
      using errcode = 'P0001';
  end if;

  perform public.rate_limit_hit(p_action);
end;
$$;

comment on function public.consume_app_rate_limit(text) is
  'Authenticated client entry point for app-level rate limits (whitelist only).';

revoke all on function public.consume_app_rate_limit(text) from public;
grant execute on function public.consume_app_rate_limit(text) to authenticated;

-- ---------------------------------------------------------------------------
-- FIX #4 — Storage: scope avatars + screenshots to caller folder
-- ---------------------------------------------------------------------------
drop policy if exists "avatars_storage_insert" on storage.objects;
drop policy if exists "avatars_storage_insert_own" on storage.objects;
create policy "avatars_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "avatars_storage_update" on storage.objects;
drop policy if exists "avatars_storage_update_own" on storage.objects;
create policy "avatars_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "screenshots_storage_insert" on storage.objects;
drop policy if exists "screenshots_storage_insert_own" on storage.objects;
create policy "screenshots_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "screenshots_storage_update" on storage.objects;
drop policy if exists "screenshots_storage_update_own" on storage.objects;
create policy "screenshots_storage_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
