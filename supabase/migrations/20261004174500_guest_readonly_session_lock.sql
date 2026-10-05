-- Explore as Guest write lock.
-- A guest token is a normal authenticated JWT whose session_id is not in
-- auth.sessions (the issuer deletes the row before returning the token).
-- GoTrue then rejects Auth user updates. This pre-request rejects Data API
-- writes. A live password/OAuth session still has its row, so it is unchanged.
-- A JWT may also set guest_readonly=true; that is locked even if a session row exists.

create or replace function public.guest_session_is_read_only()
returns boolean
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  claims jsonb;
  sid text;
  sid_uuid uuid;
begin
  claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  if claims is null then
    return false;
  end if;

  if lower(coalesce(claims->>'guest_readonly', '')) in ('true', 't', '1') then
    return true;
  end if;

  if coalesce(claims->>'role', '') is distinct from 'authenticated' then
    return false;
  end if;

  sid := nullif(btrim(claims->>'session_id'), '');
  if sid is null or sid = '00000000-0000-0000-0000-000000000000' then
    return false;
  end if;

  begin
    sid_uuid := sid::uuid;
  exception
    when invalid_text_representation then
      return true;
  end;

  return not exists (
    select 1
    from auth.sessions s
    where s.id = sid_uuid
  );
end;
$$;

comment on function public.guest_session_is_read_only() is
  'True for a guest_readonly JWT, or an authenticated JWT whose session_id is not a live auth.sessions row.';

revoke all on function public.guest_session_is_read_only() from public;
grant execute on function public.guest_session_is_read_only() to anon, authenticated, service_role;

create or replace function public.enforce_guest_readonly()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  method text := upper(coalesce(current_setting('request.method', true), ''));
  path text := coalesce(current_setting('request.path', true), '');
  fn text;
  writes boolean;
begin
  if not public.guest_session_is_read_only() then
    return;
  end if;

  if method in ('GET', 'HEAD', 'OPTIONS') then
    return;
  end if;

  path := regexp_replace(path, '^/rest/v1', '');
  if method = 'POST' and path ~ '^/rpc/[^/?]+' then
    fn := substring(path from '^/rpc/([^/?]+)');
    select coalesce(bool_or(
      p.provolatile = 'v'
      and p.prosrc ~* '(insert[[:space:]]+into|delete[[:space:]]+from|update[[:space:]]+[a-z_"])'
    ), true)
    into writes
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = fn;

    if not coalesce(writes, true) then
      return;
    end if;
  end if;

  raise exception 'guest_readonly' using errcode = '42501';
end;
$$;

comment on function public.enforce_guest_readonly() is
  'PostgREST pre-request. Guest sessions may GET and call non-writing RPCs. Everything else raises guest_readonly.';

revoke all on function public.enforce_guest_readonly() from public;
grant execute on function public.enforce_guest_readonly() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request = 'public.enforce_guest_readonly';
notify pgrst, 'reload config';

-- Storage does not use the pre-request hook.
drop policy if exists guest_readonly_no_storage_insert on storage.objects;
create policy guest_readonly_no_storage_insert
  on storage.objects
  as restrictive
  for insert
  to authenticated
  with check (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_storage_update on storage.objects;
create policy guest_readonly_no_storage_update
  on storage.objects
  as restrictive
  for update
  to authenticated
  using (not public.guest_session_is_read_only())
  with check (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_storage_delete on storage.objects;
create policy guest_readonly_no_storage_delete
  on storage.objects
  as restrictive
  for delete
  to authenticated
  using (not public.guest_session_is_read_only());

create or replace function public.guest_release_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = auth, public
as $$
begin
  if p_session_id is null then
    raise exception 'session_required' using errcode = '22023';
  end if;
  delete from auth.refresh_tokens where session_id = p_session_id;
  delete from auth.sessions where id = p_session_id;
end;
$$;

comment on function public.guest_release_session(uuid) is
  'Service-role only. Drops a just-issued guest session so the access token cannot call GoTrue user routes.';

revoke all on function public.guest_release_session(uuid) from public, anon, authenticated;
grant execute on function public.guest_release_session(uuid) to service_role;
