-- Expand conversation shared media beyond direct message.image_url attachments.
-- SECURITY INVOKER is intentional: linked trades/posts/reels continue to obey
-- their existing RLS policies in addition to the conversation membership check.

create or replace function public.try_story_reply_image_url(p_content text)
returns text
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  return nullif(btrim((p_content::jsonb ->> 'story_image_url')), '');
exception
  when others then
    return null;
end;
$$;

revoke all on function public.try_story_reply_image_url(text) from public;
grant execute on function public.try_story_reply_image_url(text) to authenticated;

create or replace function public.get_conversation_shared_media(
  p_conversation_id uuid,
  p_before_created_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 12
)
returns table (
  message_id uuid,
  sender_id uuid,
  image_url text,
  created_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  page_size integer := least(greatest(coalesce(p_limit, 12), 1), 12);
begin
  if caller is null
     or not public.is_conversation_participant(p_conversation_id, caller) then
    raise exception 'Conversation media is available to current members only';
  end if;

  return query
  select
    m.id,
    m.sender_id,
    media.image_url,
    -- messages.created_at is timestamp (no tz); RETURN QUERY does not implicitly
    -- cast, so an explicit cast is required to satisfy the timestamptz out column.
    m.created_at::timestamptz
  from public.messages m
  left join public.trades t on t.id = m.trade_id
  left join public.posts p on p.id = m.post_id
  left join public.profile_posts pp on pp.id = m.profile_post_id
  left join public.reels r on r.id = m.reel_id
  cross join lateral (
    values (
      coalesce(
        nullif(btrim(m.image_url), ''),
        nullif(btrim(t.image_url), ''),
        nullif(btrim(p.image_url), ''),
        nullif(btrim(pp.image_url), ''),
        nullif(btrim(r.thumbnail_url), ''),
        case
          when m.type = 'story_reply'
            then public.try_story_reply_image_url(m.content)
          else null
        end
      )
    )
  ) as media(image_url)
  where m.conversation_id = p_conversation_id
    and media.image_url is not null
    and coalesce(m.deleted_for_everyone, false) = false
    and not exists (
      select 1
      from public.message_deletions md
      where md.message_id = m.id
        and md.user_id = caller
    )
    and (
      p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    )
  order by m.created_at desc, m.id desc
  limit page_size;
end;
$$;

revoke all on function public.get_conversation_shared_media(uuid, timestamptz, uuid, integer)
  from public;
grant execute on function public.get_conversation_shared_media(uuid, timestamptz, uuid, integer)
  to authenticated;
