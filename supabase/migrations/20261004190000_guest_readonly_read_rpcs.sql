-- Guest sessions may call production read bootstraps that optionally mark
-- notifications or rooms read. Those side effects no-op for guest_readonly.
-- The pre-request still rejects every other volatile write, including
-- SECURITY DEFINER mutations. HTTP method is not the classifier.

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

    -- Read bootstraps. Their only writes are mark-read side effects, and those
    -- branches check guest_session_is_read_only() before writing.
    if fn in (
      'rpc_v2_messaging_bootstrap',
      'rpc_v1_conversation_thread_bootstrap',
      'rpc_v1_room_bootstrap'
    ) then
      return;
    end if;

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
  'PostgREST pre-request. Guest sessions may GET, call non-writing RPCs, and call the read bootstraps whose mark-read side effects no-op for guests. Everything else raises guest_readonly.';

do $patch$
declare
  def text;
  next text;
begin
  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v2_messaging_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_limit integer, p_cursor text, p_mark_message_notifications_read boolean';
  if def is null then
    raise exception 'rpc_v2_messaging_bootstrap missing';
  end if;
  next := replace(
    def,
    $old$if p_mark_message_notifications_read is true
     and (p_cursor is null or btrim(p_cursor) = '') then$old$,
    $new$if p_mark_message_notifications_read is true
     and not public.guest_session_is_read_only()
     and (p_cursor is null or btrim(p_cursor) = '') then$new$
  );
  if next = def then
    raise exception 'messaging bootstrap mark-read guard was not found';
  end if;
  execute next;

  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_conversation_thread_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_conversation_id uuid, p_message_limit integer, p_cursor text, p_mark_read boolean';
  if def is null then
    raise exception 'rpc_v1_conversation_thread_bootstrap missing';
  end if;
  next := replace(
    def,
    'if p_mark_read then',
    'if p_mark_read and not public.guest_session_is_read_only() then'
  );
  if next = def then
    raise exception 'conversation thread mark-read guard was not found';
  end if;
  execute next;

  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_room_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_room_id uuid, p_section_id uuid, p_message_limit integer, p_mark_read boolean';
  if def is null then
    raise exception 'rpc_v1_room_bootstrap missing';
  end if;
  next := replace(
    def,
    'if p_mark_read and v_is_member then',
    'if p_mark_read and v_is_member and not public.guest_session_is_read_only() then'
  );
  if next = def then
    raise exception 'room bootstrap mark-read guard was not found';
  end if;
  execute next;
end
$patch$;
