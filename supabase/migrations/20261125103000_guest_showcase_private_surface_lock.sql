-- Guest showcase sessions: block private inbox/notification surfaces while keeping
-- journal + public community reads for the shared showcase account.
-- Real owner sessions retain live auth.sessions rows → guest_session_is_read_only() is false.

-- -----------------------------------------------------------------------------
-- 1) PostgREST pre-request: drop member messaging bootstraps for guest tokens.
-- -----------------------------------------------------------------------------
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

    -- Private messaging / membership bootstraps must not run on guest tokens.
    if fn in (
      'rpc_v2_messaging_bootstrap',
      'rpc_v1_conversation_thread_bootstrap',
      'rpc_v1_room_bootstrap'
    ) then
      raise exception 'guest_readonly' using errcode = '42501';
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
  'PostgREST pre-request. Guest tokens: GET + non-writing RPCs only. Member messaging bootstraps rejected.';

-- -----------------------------------------------------------------------------
-- 2) RPC guards — return empty envelopes instead of showcase-private inbox data.
-- -----------------------------------------------------------------------------
do $patch$
declare
  def text;
  next text;
  guard text := $guard$
  if public.guest_session_is_read_only() then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_uid
      ),
      'data', jsonb_build_object(
        'conversations', '[]'::jsonb,
        'peers', '{}'::jsonb,
        'dm_unread_total', 0,
        'muted_ids', '[]'::jsonb,
        'message_notifications_marked_read', 0,
        'next_cursor', null,
        'page_meta', jsonb_build_object('limit', 0, 'returned', 0, 'has_more', false)
      )
    );
  end if;

$guard$;
  activity_guard text := $guard$
  if public.guest_session_is_read_only() then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 'v1',
        'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'viewer_id', v_uid::text
      ),
      'data', jsonb_build_object(
        'notifications', '[]'::jsonb,
        'actors', '{}'::jsonb,
        'follow_requests', '[]'::jsonb,
        'unread_total', 0,
        'next_cursor', null
      )
    );
  end if;

$guard$;
begin
  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v2_messaging_bootstrap'
    and pg_get_function_identity_arguments(p.oid) = 'p_limit integer, p_cursor text, p_mark_message_notifications_read boolean';
  if def is null then
    raise exception 'rpc_v2_messaging_bootstrap missing';
  end if;
  if def not like '%guest_session_is_read_only()%' then
    next := replace(def, $needle$  if v_uid is null then$needle$, guard || $needle$  if v_uid is null then$needle$);
    if next = def then
      raise exception 'rpc_v2_messaging_bootstrap guest guard anchor not found';
    end if;
    execute next;
  end if;

  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_activity_bootstrap';
  if def is null then
    raise exception 'rpc_v1_activity_bootstrap missing';
  end if;
  if def not like '%guest_session_is_read_only()%' then
    next := replace(def, $needle$  if v_uid is null then$needle$, activity_guard || $needle$  if v_uid is null then$needle$);
    if next = def then
      raise exception 'rpc_v1_activity_bootstrap guest guard anchor not found';
    end if;
    execute next;
  end if;
end
$patch$;

-- -----------------------------------------------------------------------------
-- 3) Restrictive RLS — hide private messaging + notifications + broker secrets.
-- -----------------------------------------------------------------------------
drop policy if exists guest_readonly_no_notifications_select on public.notifications;
create policy guest_readonly_no_notifications_select
  on public.notifications
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_conversations_select on public.conversations;
create policy guest_readonly_no_conversations_select
  on public.conversations
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_conversation_participants_select on public.conversation_participants;
create policy guest_readonly_no_conversation_participants_select
  on public.conversation_participants
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_messages_select on public.messages;
create policy guest_readonly_no_messages_select
  on public.messages
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_broker_connections_select on public.broker_integration_connections;
create policy guest_readonly_no_broker_connections_select
  on public.broker_integration_connections
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());

drop policy if exists guest_readonly_no_admin_users_select on public.admin_users;
create policy guest_readonly_no_admin_users_select
  on public.admin_users
  as restrictive
  for select
  to authenticated
  using (not public.guest_session_is_read_only());