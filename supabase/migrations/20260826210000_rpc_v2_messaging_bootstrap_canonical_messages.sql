-- Repair: rpc_v2_messaging_bootstrap reads latest activity from canonical public.messages
-- instead of denormalized conversations.last_message / last_message_at.
--
-- Inbox preview, timestamp, sender, and ordering derive from the same row as the thread RPC.
-- Denormalized conversation columns remain for legacy REST paths but are non-authoritative.

create or replace function public._v2_messaging_inbox_preview_text(
  p_deleted_for_everyone boolean,
  p_is_system boolean,
  p_type text,
  p_content text,
  p_image_url text,
  p_trade_id uuid
)
returns text
language sql
immutable
security invoker
set search_path = public, pg_temp
as $$
  select case
    when coalesce(p_deleted_for_everyone, false) then 'Message deleted'
    when coalesce(p_is_system, false) then 'System message'
    when lower(coalesce(p_type, '')) = 'trade' or p_trade_id is not null then 'Shared a trade'
    when p_image_url is not null and btrim(p_image_url) <> '' then 'Photo'
    when p_content is not null and btrim(p_content) <> '' then btrim(p_content)
    else 'New message'
  end;
$$;

revoke all on function public._v2_messaging_inbox_preview_text(
  boolean, boolean, text, text, text, uuid
) from public;
revoke all on function public._v2_messaging_inbox_preview_text(
  boolean, boolean, text, text, text, uuid
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
  -- Latest activity includes every viewer-visible message (incoming and outgoing).
  -- Never filter m.sender_id <> v_uid here — unread is computed separately below.
  latest_messages as (
    select distinct on (m.conversation_id)
      m.conversation_id,
      m.id as message_id,
      m.sender_id,
      m.created_at,
      m.type,
      m.content,
      m.image_url,
      m.trade_id,
      m.deleted_for_everyone,
      m.is_system
    from public.messages m
    inner join membership mem on mem.conversation_id = m.conversation_id
    where m.conversation_id is not null
      and (
        coalesce(m.deleted_for_everyone, false) = true
        or not exists (
          select 1
          from public.message_deletions md
          where md.message_id = m.id
            and md.user_id = v_uid
        )
      )
    order by m.conversation_id, m.created_at desc, m.id desc
  ),
  ranked as (
    select
      c.id,
      c.is_group,
      c.is_pinned,
      c.name,
      c.avatar_url,
      lm.message_id as last_message_id,
      lm.sender_id as last_message_sender_id,
      lm.created_at as last_message_at,
      public._v2_messaging_inbox_preview_text(
        lm.deleted_for_everyone,
        lm.is_system,
        lm.type,
        lm.content,
        lm.image_url,
        lm.trade_id
      ) as last_message,
      lm.type as last_message_type,
      row_number() over (
        order by
          coalesce(c.is_pinned, false) desc,
          lm.created_at desc nulls last,
          lm.message_id desc nulls last,
          c.id desc
      ) as rn
    from public.conversations c
    join membership mem on mem.conversation_id = c.id
    left join latest_messages lm on lm.conversation_id = c.id
    where public._v2_messaging_before_cursor(
      lm.created_at,
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
          'last_message_id', p.last_message_id,
          'last_message_sender_id', p.last_message_sender_id,
          'last_message_type', p.last_message_type,
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
          p.last_message_id desc nulls last,
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
  'Messaging inbox V2 — latest activity from canonical public.messages (viewer-visible rows, all senders). Unread from get_conversation_unread_counts only. Composite cursor unchanged: {last_message_at}|{conversation_id}.';

revoke all on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) from public;
revoke all on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) from anon;
grant execute on function public.rpc_v2_messaging_bootstrap(integer, text, boolean) to authenticated;

-- Optional non-authoritative backfill for legacy REST readers (idempotent, safe to re-run):
-- update public.conversations c
-- set
--   last_message = src.preview,
--   last_message_at = src.created_at
-- from (
--   select distinct on (m.conversation_id)
--     m.conversation_id,
--     m.created_at,
--     public._v2_messaging_inbox_preview_text(
--       m.deleted_for_everyone,
--       m.is_system,
--       m.type,
--       m.content,
--       m.image_url,
--       m.trade_id
--     ) as preview
--   from public.messages m
--   where m.conversation_id is not null
--     and coalesce(m.deleted_for_everyone, false) = false
--   order by m.conversation_id, m.created_at desc, m.id desc
-- ) src
-- where c.id = src.conversation_id;

-- Clear stale preview timestamps on empty conversations:
-- update public.conversations c
-- set last_message = null, last_message_at = null
-- where not exists (
--   select 1 from public.messages m where m.conversation_id = c.id
-- );
