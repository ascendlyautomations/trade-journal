-- Trade Room voice messages: bootstrap / guest message projections must expose audio metadata.
-- DMs already include audio in rpc_v1_conversation_thread_message_row (20260901230000_voice_messages).

create or replace function public.rpc_v1_room_bootstrap_message_row(p_message_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', m.id,
    'room_id', m.room_id,
    'user_id', m.user_id,
    'seen_by', coalesce(m.seen_by, '[]'::jsonb),
    'pinned', coalesce(m.pinned, false),
    'section_id', m.section_id,
    'parent_message_id', m.parent_message_id,
    'type', m.type,
    'trade_id', m.trade_id,
    'content', m.content,
    'image_url', m.image_url,
    'audio_url', m.audio_url,
    'audio_duration_ms', m.audio_duration_ms,
    'created_at', case
      when m.created_at is null then null
      else to_char(timezone('utc', m.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    end,
    'trades', case
      when m.trade_id is null then null
      else jsonb_build_object('id', m.trade_id)
    end,
    'profiles', (
      select jsonb_build_object(
        'username', pr.username,
        'avatar_url', pr.avatar_url
      )
      from public.profiles pr
      where pr.id = m.user_id
    ),
    'room_message_reactions', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', r.id,
            'message_id', r.message_id,
            'user_id', r.user_id,
            'reaction', r.reaction
          )
          order by r.created_at asc, r.id asc
        )
        from public.room_message_reactions r
        where r.message_id = m.id
      ),
      '[]'::jsonb
    )
  )
  from public.room_messages m
  where m.id = p_message_id
    and public.profile_is_visible_to_viewer(m.user_id);
$$;

create or replace function public.rpc_v1_public_room_guest_message_row(
  p_message_id uuid,
  p_room_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not public._v1_trade_room_guest_readable(r) then null
    when m.id is null or m.room_id is distinct from p_room_id then null
    when coalesce(m.pinned, false) then null
    else jsonb_build_object(
      'id', m.id,
      'room_id', m.room_id,
      'section_id', m.section_id,
      'parent_message_id', m.parent_message_id,
      'type', m.type,
      'content', m.content,
      'image_url', m.image_url,
      'audio_url', m.audio_url,
      'audio_duration_ms', m.audio_duration_ms,
      'created_at', case
        when m.created_at is null then null
        else to_char(timezone('utc', m.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      end,
      'trade_id', case
        when m.trade_id is null then null
        when tx.id is not null and coalesce(tx.is_public, false) then m.trade_id
        else null
      end,
      'trades', case
        when m.trade_id is null then null
        when tx.id is not null and coalesce(tx.is_public, false) then jsonb_build_object('id', tx.id)
        else null
      end,
      'profiles', case
        when pr.id is null or coalesce(pr.is_private, false) then null
        else jsonb_build_object(
          'username', pr.username,
          'avatar_url', pr.avatar_url
        )
      end,
      'room_message_reactions', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'reaction', agg.reaction,
              'count', agg.reaction_count
            )
            order by agg.reaction asc
          )
          from (
            select r.reaction, count(*)::int as reaction_count
            from public.room_message_reactions r
            where r.message_id = m.id
            group by r.reaction
          ) agg
        ),
        '[]'::jsonb
      )
    )
  end
  from public.rooms r
  join public.room_messages m
    on m.id = p_message_id
    and m.room_id = p_room_id
    and public.profile_is_visible_to_viewer(m.user_id)
  left join public.profiles pr
    on pr.id = m.user_id
    and coalesce(pr.is_private, false) = false
  left join public.trades tx
    on tx.id = m.trade_id
    and coalesce(tx.is_public, false) = true
  where r.id = p_room_id;
$$;
