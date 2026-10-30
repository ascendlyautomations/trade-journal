-- Smoke verification after full clone restore (staging).
\set ON_ERROR_STOP on

do $$
declare
  n bigint;
begin
  select count(*) into n from auth.users;
  if n < 1 then
    raise exception 'Expected auth.users rows after full clone (got %)', n;
  end if;

  select count(*) into n from public.profiles;
  if n < 1 then
    raise exception 'Expected public.profiles rows (got %)', n;
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public' and p.proname = 'handle_new_user'
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

select 'full_clone_verify passed' as result;
