-- Phase C hardening: optimized Messaging inbox RPC (V2). V1 remains unchanged for legacy clients.

create index if not exists notifications_user_id_message_unread_idx
  on public.notifications (user_id)
  where read = false and type = 'message';

create or replace function public._v2_messaging_parse_cursor(p_cursor text)
returns table (
  cursor_ts timestamptz,
  cursor_id uuid,
  legacy_only boolean
)
language plpgsql
immutable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_parts text[];
begin
  if p_cursor is null or btrim(p_cursor) = '' then
    return;
  end if;

  if position('|' in p_cursor) > 0 then
    v_parts := string_to_array(p_cursor, '|');
    if coalesce(array_length(v_parts, 1), 0) >= 2 then
      cursor_ts := v_parts[1]::timestamptz;
      cursor_id := v_parts[2]::uuid;
      legacy_only := false;
      return next;
      return;
    end if;
  end if;

  cursor_ts := p_cursor::timestamptz;
  cursor_id := null;
  legacy_only := true;
  return next;
end;
$$;

revoke all on function public._v2_messaging_parse_cursor(text) from public;
revoke all on function public._v2_messaging_parse_cursor(text) from anon;

create or replace function public._v2_messaging_before_cursor(
  p_row_ts timestamptz,
  p_row_id uuid,
  p_cursor_ts timestamptz,
  p_cursor_id uuid,
  p_legacy_only boolean
)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select
    p_cursor_ts is null
    or (
      p_legacy_only
      and p_row_ts is not null
      and p_row_ts < p_cursor_ts
    )
    or (
      not coalesce(p_legacy_only, false)
      and (
        p_row_ts is null
        or p_row_ts < p_cursor_ts
        or (
          p_row_ts = p_cursor_ts
          and p_row_id < p_cursor_id
        )
      )
    );
$$;

revoke all on function public._v2_messaging_before_cursor(
  timestamptz, uuid, timestamptz, uuid, boolean
) from public;
revoke all on function public._v2_messaging_before_cursor(
  timestamptz, uuid, timestamptz, uuid, boolean
) from anon;

create or replace function public.rpc_v2_messaging_bootstrap(
  p_limit integer,
  p_cursor text,
  p_mark_message_notifications_read boolean
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 40), 80));
  v_cursor_ts timestamptz;
  v_cursor_id uuid;
  v_cursor_legacy boolean := true;
  v_marked_notifications integer := 0;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select c.cursor_ts, c.cursor_id, c.legacy_only
  into v_cursor_ts, v_cursor_id, v_cursor_legacy
  from public._v2_messaging_parse_cursor(p_cursor) c;

  if p_mark_message_notifications_read is true
     and (p_cursor is null or btrim(p_cursor) = '') then
    update public.notifications n
    set read = true
    where n.user_id = v_uid
      and n.type = 'message'
      and n.read = false;
    get diagnostics v_marked_notifications = row_count;
  end if;

  with
  blocked as (
    select b.conversation_id
    from public.get_hidden_blocked_dm_conversation_ids() b
  ),
  membership as (
    select cp.conversation_id
    from public.conversation_participants cp
    where cp.user_id = v_uid
      and not exists (
        select 1
        from blocked b
        where b.conversation_id = cp.conversation_id
      )
  ),
  muted as (
    select cmp.conversation_id
    from public.conversation_member_preferences cmp
    where cmp.user_id = v_uid
      and cmp.notifications_enabled = false
      and cmp.conversation_id in (select m.conversation_id from membership m)
  ),
  ranked as (
    select
      c.id,
      c.is_group,
      c.is_pinned,
      c.name,
      c.avatar_url,
      c.last_message,
      c.last_message_at,
      row_number() over (
        order by
          coalesce(c.is_pinned, false) desc,
          c.last_message_at desc nulls last,
          c.id desc
      ) as rn
    from public.conversations c
    join membership mem on mem.conversation_id = c.id
    where public._v2_messaging_before_cursor(
      c.last_message_at,
      c.id,
      v_cursor_ts,
      v_cursor_id,
      v_cursor_legacy
    )
  ),
  page as (
    select r.*
    from ranked r
    where r.rn <= (v_limit + 1)
  ),
  page_rows as (
    select p.*
    from page p
    where p.rn <= v_limit
  ),
  page_ids as (
    select pr.id
    from page_rows pr
  ),
  unread_all as (
    select u.conversation_id, u.unread_count
    from public.get_conversation_unread_counts(
      (select coalesce(array_agg(m.conversation_id), '{}'::uuid[]) from membership m)
    ) u
  ),
  participants as (
    select
      cp.conversation_id,
      jsonb_agg(
        jsonb_build_object(
          'user_id', cp.user_id,
          'username', pr.username,
          'display_name', coalesce(pr.name, pr.username),
          'avatar_url', pr.avatar_url
        )
        order by cp.user_id
      ) as participants_json
    from public.conversation_participants cp
    left join public.profiles pr on pr.id = cp.user_id
    where cp.conversation_id in (select pi.id from page_ids pi)
    group by cp.conversation_id
  ),
  peers as (
    select
      coalesce(
        jsonb_object_agg(
          pr.id::text,
          jsonb_build_object(
            'id', pr.id,
            'username', pr.username,
            'display_name', coalesce(pr.name, pr.username),
            'avatar_url', pr.avatar_url
          )
        ),
        '{}'::jsonb
      ) as peers_json
    from (
      select distinct cp.user_id
      from public.conversation_participants cp
      where cp.conversation_id in (select pi.id from page_ids pi)
        and cp.user_id <> v_uid
    ) u
    join public.profiles pr on pr.id = u.user_id
  ),
  conv_json as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'is_group', coalesce(p.is_group, false),
          'is_pinned', coalesce(p.is_pinned, false),
          'name', p.name,
          'avatar_url', p.avatar_url,
          'last_message', p.last_message,
          'last_message_at', case
            when p.last_message_at is null then null
            else to_char(timezone('utc', p.last_message_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          end,
          'unread_count', case
            when exists (select 1 from muted m where m.conversation_id = p.id)
              then 0
            else coalesce(up.unread_count, 0)::integer
          end,
          'muted', exists (select 1 from muted m where m.conversation_id = p.id),
          'participants', coalesce(pt.participants_json, '[]'::jsonb)
        )
        order by
          coalesce(p.is_pinned, false) desc,
          p.last_message_at desc nulls last,
          p.id desc
      ),
      '[]'::jsonb
    ) as conversations
    from page_rows p
    left join unread_all up on up.conversation_id = p.id
    left join participants pt on pt.conversation_id = p.id
  ),
  totals as (
    select coalesce(sum(
      case
        when exists (select 1 from muted m where m.conversation_id = ua.conversation_id)
          then 0
        else ua.unread_count
      end
    ), 0)::integer as dm_unread_total
    from unread_all ua
  ),
  meta_page as (
    select
      (select count(*)::integer from page_rows) as returned,
      exists (select 1 from page pg where pg.rn = v_limit + 1) as has_more,
      (
        select jsonb_build_object(
          'last_message_at', pr.last_message_at,
          'id', pr.id
        )
        from page_rows pr
        order by pr.rn desc
        limit 1
      ) as last_row
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'conversations', (select cj.conversations from conv_json cj),
      'peers', (select p.peers_json from peers p),
      'dm_unread_total', (select t.dm_unread_total from totals t),
      'muted_ids', coalesce(
        (select jsonb_agg(m.conversation_id::text) from muted m),
        '[]'::jsonb
      ),
      'message_notifications_marked_read', v_marked_notifications,
      'next_cursor', case
        when (select mp.has_more from meta_page mp)
          and (select mp.last_row from meta_page mp) is not null
          and ((select mp.last_row from meta_page mp) ->> 'last_message_at') is not null
          then (
            to_char(
              timezone(
                'utc',
                ((select mp.last_row from meta_page mp) ->> 'last_message_at')::timestamptz
              ),
              'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            )
            || '|'
            || ((select mp.last_row from meta_page mp) ->> 'id')
          )
        else null
      end,
      'page_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', (select mp.returned from meta_page mp),
        'has_more', (select mp.has_more from meta_page mp)
      )
    )
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) is
  'Phase C Messaging inbox V2 — composite cursor + optional inbox-open message notification mark-read. V1 clients remain on rpc_v1_messaging_bootstrap.';

revoke all on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) from public;
revoke all on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) from anon;
grant execute on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) to authenticated;
