-- Run against staging after baseline restore (and again after forward migrations).
-- psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/staging/verify/schema_verification.sql

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------
-- 1. Core tables present (legacy baseline — not created by repo migrations)
-- ---------------------------------------------------------------------------
do $$
declare
  missing text[];
  required constant text[] := array[
    'profiles','trades','accounts','rooms','room_messages','messages',
    'conversations','followers','admin_users','achievements'
  ];
  t text;
begin
  foreach t in array required loop
    if not exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = t
    ) then
      missing := array_append(missing, t);
    end if;
  end loop;
  if array_length(missing, 1) is not null then
    raise exception 'Missing public tables: %', array_to_string(missing, ', ');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Signup path
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'handle_new_user'
  ) then
    raise exception 'Missing public.handle_new_user()';
  end if;
  if not exists (
    select 1 from pg_trigger tg
    join pg_class c on c.oid = tg.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'auth' and c.relname = 'users' and tg.tgname = 'on_auth_user_created'
  ) then
    raise exception 'Missing auth.on_auth_user_created trigger';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. RLS enabled on public tables
-- ---------------------------------------------------------------------------
do $$
declare
  open_rls bigint;
begin
  select count(*) into open_rls
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  if open_rls > 0 then
    raise exception 'Found % public tables without RLS', open_rls;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Storage buckets (including migration gaps)
-- ---------------------------------------------------------------------------
do $$
declare
  missing text[];
  required constant text[] := array[
    'avatars','screenshots','profile_posts','stories','reels','csv-support',
    'message-audio','draft-media','demo-media','bug-reports','email-assets','group-avatars'
  ];
  b text;
begin
  foreach b in array required loop
    if not exists (select 1 from storage.buckets where id = b) then
      missing := array_append(missing, b);
    end if;
  end loop;
  if array_length(missing, 1) is not null then
    raise exception 'Missing storage buckets: %', array_to_string(missing, ', ');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Critical RPCs (Web/iOS bootstraps)
-- ---------------------------------------------------------------------------
do $$
declare
  missing text[];
  required constant text[] := array[
    'rpc_v1_session_bootstrap',
    'rpc_v1_dashboard_bootstrap',
    'rpc_v1_feed_bootstrap',
    'rpc_v2_messaging_bootstrap',
    'rpc_v1_trades_list_bootstrap'
  ];
  r text;
begin
  foreach r in array required loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = r
    ) then
      missing := array_append(missing, r);
    end if;
  end loop;
  if array_length(missing, 1) is not null then
    raise exception 'Missing RPC functions: %', array_to_string(missing, ', ');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. Realtime publication (subset smoke — expand as needed)
-- ---------------------------------------------------------------------------
do $$
declare
  missing text[];
  required constant text[] := array['trades','messages','notifications','profiles'];
  t text;
begin
  foreach t in array required loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      missing := array_append(missing, t);
    end if;
  end loop;
  if array_length(missing, 1) is not null then
    raise exception 'Tables not in supabase_realtime publication: %', array_to_string(missing, ', ');
  end if;
end $$;

select 'schema_verification (baseline) passed' as result;
