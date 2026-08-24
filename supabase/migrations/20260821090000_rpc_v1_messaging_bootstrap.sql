-- Backend V2 Phase 6: Messaging inbox bootstrap (single JSON for Messaging-owned data).
-- SECURITY DEFINER — same pattern as get_conversation_unread_counts / get_hidden_blocked.
-- Constrained to auth.uid(). Does NOT include Session/Dashboard/Feed/Rooms fields.
-- Aggregate dm_unread_total is computed here for Session badge patch (Messaging owns computation).

create or replace function public.rpc_v1_messaging_bootstrap(
  p_limit integer default 40,
  p_cursor timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 40), 80));
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  with
  blocked as (
    select conversation_id
    from public.get_hidden_blocked_dm_conversation_ids()
  ),
  membership as (
    select cp.conversation_id
    from public.conversation_participants cp
    where cp.user_id = v_uid
      and not exists (
        select 1 from blocked b where b.conversation_id = cp.conversation_id
      )
  ),
  muted as (
    select cmp.conversation_id
    from public.conversation_member_preferences cmp
    where cmp.user_id = v_uid
      and cmp.notifications_enabled = false
      and cmp.conversation_id in (select conversation_id from membership)
  ),
  unread_raw as (
    select u.conversation_id, u.unread_count
    from public.get_conversation_unread_counts(
      (select coalesce(array_agg(conversation_id), '{}'::uuid[]) from membership)
    ) u
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
      case
        when exists (select 1 from muted m where m.conversation_id = c.id)
          then 0
        else coalesce(ur.unread_count, 0)::integer
      end as unread_count,
      exists (select 1 from muted m where m.conversation_id = c.id) as muted,
      row_number() over (
        order by
          coalesce(c.is_pinned, false) desc,
          c.last_message_at desc nulls last,
          c.id desc
      ) as rn
    from public.conversations c
    join membership mem on mem.conversation_id = c.id
    left join unread_raw ur on ur.conversation_id = c.id
    where p_cursor is null
       or (
         c.last_message_at is not null
         and c.last_message_at < p_cursor
       )
  ),
  page as (
    select *
    from ranked
    where rn <= (v_limit + 1)
  ),
  page_ids as (
    select id from page where rn <= v_limit
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
    where cp.conversation_id in (select id from page_ids)
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
      where cp.conversation_id in (select id from page_ids)
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
          'unread_count', p.unread_count,
          'muted', p.muted,
          'participants', coalesce(pt.participants_json, '[]'::jsonb)
        )
        order by
          coalesce(p.is_pinned, false) desc,
          p.last_message_at desc nulls last,
          p.id desc
      ),
      '[]'::jsonb
    ) as conversations
    from page p
    left join participants pt on pt.conversation_id = p.id
    where p.rn <= v_limit
  ),
  totals as (
    select coalesce(sum(
      case
        when exists (select 1 from muted m where m.conversation_id = ur.conversation_id)
          then 0
        else ur.unread_count
      end
    ), 0)::integer as dm_unread_total
    from unread_raw ur
  ),
  meta_page as (
    select
      (select count(*)::integer from page where rn <= v_limit) as returned,
      exists (select 1 from page where rn = v_limit + 1) as has_more,
      (
        select last_message_at
        from page
        where rn = v_limit
        limit 1
      ) as next_cursor_ts
  )
  select jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 'v1',
      'server_time', to_char(timezone('utc', now()), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'viewer_id', v_uid
    ),
    'data', jsonb_build_object(
      'conversations', (select conversations from conv_json),
      'peers', (select peers_json from peers),
      'dm_unread_total', (select dm_unread_total from totals),
      'muted_ids', coalesce(
        (select jsonb_agg(conversation_id::text) from muted),
        '[]'::jsonb
      ),
      'next_cursor', case
        when (select has_more from meta_page) and (select next_cursor_ts from meta_page) is not null
          then to_char(
            timezone('utc', (select next_cursor_ts from meta_page)),
            'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
          )
        else null
      end,
      'page_meta', jsonb_build_object(
        'limit', v_limit,
        'returned', (select returned from meta_page),
        'has_more', (select has_more from meta_page)
      )
    )
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.rpc_v1_messaging_bootstrap(integer, timestamptz) from public;
grant execute on function public.rpc_v1_messaging_bootstrap(integer, timestamptz) to authenticated;

comment on function public.rpc_v1_messaging_bootstrap(integer, timestamptz) is
  'Backend V2 Messaging inbox bootstrap — conversations, unread, peers. Session owns aggregate badge storage.';
