-- Story likes, views, owner insights RPC, notification wiring, 24h visibility + 30d owner metadata retention.

-- =============================================================================
-- Helpers (visibility, storage, lifecycle)
-- =============================================================================

create or replace function public.story_is_publicly_active(p_created_at timestamptz)
returns boolean
language sql
stable
set search_path = public
as $$
  select p_created_at > now() - interval '24 hours';
$$;

comment on function public.story_is_publicly_active(timestamptz) is
  'True while a story is inside the 24h public viewing window (matches lib/activeStories.ts).';

create or replace function public.story_activity_retention_cutoff()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select now() - interval '24 hours' - interval '30 days';
$$;

comment on function public.story_activity_retention_cutoff() is
  'Stories older than this may be purged (30 days after the 24h public window).';

create or replace function public.story_storage_path_from_image_url(p_image_url text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_marker constant text := '/storage/v1/object/public/stories/';
  v_idx integer;
  v_raw text;
begin
  if p_image_url is null or btrim(p_image_url) = '' then
    return null;
  end if;
  v_idx := position(v_marker in p_image_url);
  if v_idx <= 0 then
    return null;
  end if;
  v_raw := split_part(substring(p_image_url from v_idx + length(v_marker)), '?', 1);
  if v_raw = '' or v_raw like '%..%' or left(v_raw, 1) = '/' then
    return null;
  end if;
  return v_raw;
end;
$$;

comment on function public.story_storage_path_from_image_url(text) is
  'Extracts the storage.objects.name path for the public stories bucket from image_url.';

create or replace function public.viewer_can_see_story_row(p_story public.stories)
returns boolean
language sql
stable
set search_path = public
as $$
  select
  p_story.user_id = auth.uid()
  or (
    public.story_is_publicly_active(p_story.created_at)
    and (
      auth.uid() is null
      or not (p_story.user_id = any (public.rls_viewer_block_peer_ids()))
    )
    and (
      exists (
        select 1
        from public.profiles p
        where p.id = p_story.user_id
          and coalesce(p.is_private, false) = false
      )
      or (
        auth.uid() is not null
        and exists (
          select 1
          from public.followers f
          where f.following_id = p_story.user_id
            and f.follower_id = auth.uid()
        )
      )
    )
  );
$$;

comment on function public.viewer_can_see_story_row(public.stories) is
  'Story visibility for the current auth context (owner, active window, blocks, privacy, follow).';

create or replace function public.viewer_may_engage_with_story(p_story_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.stories s
    where s.id = p_story_id
      and auth.uid() is not null
      and s.user_id <> auth.uid()
      and public.story_is_publicly_active(s.created_at)
      and public.viewer_can_see_story_row(s)
  );
$$;

comment on function public.viewer_may_engage_with_story(uuid) is
  'Non-owner may like/view an active story (privacy + blocks enforced).';

create or replace function public.story_storage_object_readable(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.stories s
    where public.story_is_publicly_active(s.created_at)
      and public.story_storage_path_from_image_url(s.image_url) = p_name
      and (
        s.user_id = auth.uid()
        or (
          (auth.uid() is null or not (s.user_id = any (public.rls_viewer_block_peer_ids())))
          and (
            exists (
              select 1
              from public.profiles p
              where p.id = s.user_id
                and coalesce(p.is_private, false) = false
            )
            or (
              auth.uid() is not null
              and exists (
                select 1
                from public.followers f
                where f.following_id = s.user_id
                  and f.follower_id = auth.uid()
              )
            )
          )
        )
      )
  );
$$;

comment on function public.story_storage_object_readable(text) is
  'Storage gateway: story bucket objects are readable only while linked to an active, visible story.';

revoke all on function public.story_storage_object_readable(text) from public;
grant execute on function public.story_storage_object_readable(text) to anon, authenticated;

revoke all on function public.story_is_publicly_active(timestamptz) from public;
grant execute on function public.story_is_publicly_active(timestamptz) to anon, authenticated;

revoke all on function public.viewer_can_see_story_row(public.stories) from public;
grant execute on function public.viewer_can_see_story_row(public.stories) to authenticated;

revoke all on function public.viewer_may_engage_with_story(uuid) from public;
grant execute on function public.viewer_may_engage_with_story(uuid) to authenticated;

-- =============================================================================
-- Stories RLS: non-owners only see active (24h) stories
-- =============================================================================

drop policy if exists "stories_select_visible" on public.stories;
create policy "stories_select_visible"
  on public.stories
  for select
  to anon, authenticated
  using (
    user_id = auth.uid()
    or (
      public.story_is_publicly_active(stories.created_at)
      and (auth.uid() is null or not (stories.user_id = any (public.rls_viewer_block_peer_ids())))
      and (
        exists (
          select 1
          from public.profiles p
          where p.id = stories.user_id
            and coalesce(p.is_private, false) = false
        )
        or (
          auth.uid() is not null
          and exists (
            select 1
            from public.followers f
            where f.following_id = stories.user_id
              and f.follower_id = auth.uid()
          )
        )
      )
    )
  );

-- =============================================================================
-- Storage: block direct URLs after story expires
-- =============================================================================

drop policy if exists "stories_storage_select" on storage.objects;
create policy "stories_storage_select"
  on storage.objects
  for select
  to anon, authenticated
  using (
    bucket_id = 'stories'
    and public.story_storage_object_readable(name)
  );

-- =============================================================================
-- Engagement tables
-- =============================================================================

create table if not exists public.story_likes (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (story_id, user_id)
);

create table if not exists public.story_views (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references auth.users (id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  unique (story_id, viewer_id)
);

create index if not exists story_likes_story_id_idx
  on public.story_likes (story_id);

create index if not exists story_views_story_id_first_viewed_idx
  on public.story_views (story_id, first_viewed_at desc);

alter table public.story_likes enable row level security;
alter table public.story_views enable row level security;

create policy story_likes_select_own
  on public.story_likes
  for select
  to authenticated
  using (user_id = auth.uid());

create policy story_likes_insert_own
  on public.story_likes
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.viewer_may_engage_with_story(story_id)
  );

create policy story_likes_delete_own
  on public.story_likes
  for delete
  to authenticated
  using (user_id = auth.uid());

-- No direct SELECT on story_views (owner uses rpc_v1_story_insights).

create policy story_views_insert_own
  on public.story_views
  for insert
  to authenticated
  with check (
    viewer_id = auth.uid()
    and public.viewer_may_engage_with_story(story_id)
  );

grant select, insert, delete on table public.story_likes to authenticated;
grant insert on table public.story_views to authenticated;

-- =============================================================================
-- Notifications
-- =============================================================================

alter table public.notifications
  add column if not exists story_id uuid references public.stories (id) on delete set null;

create index if not exists notifications_story_id_idx
  on public.notifications (story_id)
  where story_id is not null;

create unique index if not exists notifications_like_story_unique_idx
  on public.notifications (user_id, sender_id, story_id)
  where type = 'like'
    and story_id is not null;

drop policy if exists notifications_insert_like on public.notifications;
create policy notifications_insert_like
  on public.notifications
  for insert
  to authenticated
  with check (
    type = 'like'
    and sender_id = auth.uid()
    and user_id is not null
    and user_id <> auth.uid()
    and (
      (
        post_id is not null
        and comment_id is null
        and story_id is null
        and exists (
          select 1 from public.likes l
          where l.post_id = notifications.post_id and l.user_id = auth.uid()
        )
      )
      or (
        trade_id is not null
        and post_id is null
        and profile_post_id is null
        and achievement_post_id is null
        and reel_id is null
        and comment_id is null
        and story_id is null
        and exists (
          select 1 from public.trade_likes tl
          where tl.trade_id = notifications.trade_id and tl.user_id = auth.uid()
        )
      )
      or (
        profile_post_id is not null
        and comment_id is null
        and story_id is null
        and exists (
          select 1 from public.profile_post_likes ppl
          where ppl.profile_post_id = notifications.profile_post_id
            and ppl.user_id = auth.uid()
        )
      )
      or (
        achievement_post_id is not null
        and comment_id is null
        and story_id is null
        and exists (
          select 1 from public.achievement_post_likes apl
          where apl.achievement_post_id = notifications.achievement_post_id
            and apl.user_id = auth.uid()
        )
      )
      or (
        reel_id is not null
        and comment_id is null
        and story_id is null
        and exists (
          select 1 from public.reel_likes rl
          where rl.reel_id = notifications.reel_id and rl.user_id = auth.uid()
        )
      )
      or (
        story_id is not null
        and post_id is null
        and trade_id is null
        and profile_post_id is null
        and achievement_post_id is null
        and reel_id is null
        and comment_id is null
        and exists (
          select 1 from public.story_likes sl
          where sl.story_id = notifications.story_id
            and sl.user_id = auth.uid()
        )
      )
      or (
        comment_id is not null
        and story_id is null
        and exists (
          select 1 from public.comment_likes cl
          where cl.comment_source = case
            when notifications.post_id is not null then 'comments'
            when notifications.trade_id is not null
              and notifications.post_id is null
              and notifications.profile_post_id is null
              and notifications.achievement_post_id is null
              and notifications.reel_id is null
              then 'trade_comments'
            when notifications.profile_post_id is not null then 'profile_post_comments'
            when notifications.achievement_post_id is not null then 'achievement_post_comments'
            when notifications.reel_id is not null then 'reel_comments'
            else 'comments'
          end
            and cl.comment_id = notifications.comment_id
            and cl.user_id = auth.uid()
        )
      )
    )
  );

create or replace function public.sync_delete_like_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'trade_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and trade_id = old.trade_id
      and post_id is null
      and profile_post_id is null
      and achievement_post_id is null
      and reel_id is null
      and story_id is null
      and comment_id is null;
  elsif tg_table_name = 'likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and post_id = old.post_id
      and profile_post_id is null
      and achievement_post_id is null
      and reel_id is null
      and story_id is null
      and comment_id is null;
  elsif tg_table_name = 'profile_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and profile_post_id = old.profile_post_id
      and achievement_post_id is null
      and reel_id is null
      and story_id is null
      and comment_id is null;
  elsif tg_table_name = 'achievement_post_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and achievement_post_id = old.achievement_post_id
      and reel_id is null
      and story_id is null
      and comment_id is null;
  elsif tg_table_name = 'reel_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and reel_id = old.reel_id
      and story_id is null
      and comment_id is null;
  elsif tg_table_name = 'story_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and story_id = old.story_id
      and comment_id is null;
  elsif tg_table_name = 'comment_likes' then
    delete from public.notifications
    where type = 'like'
      and sender_id = old.user_id
      and comment_id = old.comment_id;
  end if;

  return old;
end;
$$;

drop trigger if exists story_likes_sync_delete_like_notification on public.story_likes;
create trigger story_likes_sync_delete_like_notification
  after delete on public.story_likes
  for each row
  execute function public.sync_delete_like_notification();

create or replace function public.rate_limit_story_likes_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;
  perform public.rate_limit_hit('like');
  return new;
end;
$$;

drop trigger if exists rate_limit_story_likes_before_insert on public.story_likes;
create trigger rate_limit_story_likes_before_insert
  before insert on public.story_likes
  for each row
  execute function public.rate_limit_story_likes_before_insert();

create or replace function public.stories_preserve_like_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications n
  set
    content = case
      when n.content is not null and btrim(n.content) ~ '^\s*\{' then
        (n.content::jsonb || jsonb_build_object(
          'story_id', old.id,
          'story_unavailable', true,
          'kind', 'story'
        ))::text
      else
        jsonb_build_object(
          'story_id', old.id,
          'story_unavailable', true,
          'kind', 'story'
        )::text
    end
  where n.story_id = old.id
    and n.type = 'like';
  return old;
end;
$$;

drop trigger if exists stories_preserve_like_notifications on public.stories;
create trigger stories_preserve_like_notifications
  before delete on public.stories
  for each row
  execute function public.stories_preserve_like_notifications();

-- =============================================================================
-- Record view (excludes owner; idempotent)
-- =============================================================================

create or replace function public.rpc_v1_story_record_view(p_story_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not public.viewer_may_engage_with_story(p_story_id) then
    return;
  end if;
  insert into public.story_views (story_id, viewer_id)
  values (p_story_id, auth.uid())
  on conflict (story_id, viewer_id) do nothing;
end;
$$;

comment on function public.rpc_v1_story_record_view(uuid) is
  'Records a unique story view for the current user (never the owner).';

revoke all on function public.rpc_v1_story_record_view(uuid) from public;
grant execute on function public.rpc_v1_story_record_view(uuid) to authenticated;

-- =============================================================================
-- Owner insights
-- =============================================================================

create or replace function public.rpc_v1_story_insights(p_story_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_view_count integer := 0;
  v_like_count integer := 0;
  v_viewers jsonb := '[]'::jsonb;
  v_likers jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select s.user_id into v_owner
  from public.stories s
  where s.id = p_story_id;

  if v_owner is null then
    raise exception 'story_not_found' using errcode = 'P0002';
  end if;

  if v_owner <> auth.uid() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select count(*)::integer into v_view_count
  from public.story_views sv
  where sv.story_id = p_story_id;

  select count(*)::integer into v_like_count
  from public.story_likes sl
  where sl.story_id = p_story_id;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.viewed_at desc), '[]'::jsonb)
  into v_viewers
  from (
    select
      p.id,
      p.username,
      p.avatar_url,
      sv.first_viewed_at as viewed_at
    from public.story_views sv
    join public.profiles p on p.id = sv.viewer_id
    where sv.story_id = p_story_id
    order by sv.first_viewed_at desc
    limit 200
  ) t;

  select coalesce(jsonb_agg(row_to_json(t)::jsonb order by t.liked_at desc), '[]'::jsonb)
  into v_likers
  from (
    select
      p.id,
      p.username,
      p.avatar_url,
      sl.created_at as liked_at,
      true as liked
    from public.story_likes sl
    join public.profiles p on p.id = sl.user_id
    where sl.story_id = p_story_id
    order by sl.created_at desc
    limit 200
  ) t;

  return jsonb_build_object(
    'meta', jsonb_build_object('contract_version', 'v1'),
    'data', jsonb_build_object(
      'story_id', p_story_id,
      'view_count', v_view_count,
      'like_count', v_like_count,
      'viewers', v_viewers,
      'likers', v_likers
    )
  );
end;
$$;

comment on function public.rpc_v1_story_insights(uuid) is
  'Owner-only story activity: viewer/like counts and profile rows.';

revoke all on function public.rpc_v1_story_insights(uuid) from public;
grant execute on function public.rpc_v1_story_insights(uuid) to authenticated;

-- =============================================================================
-- Hide-from-community parity (engagement participant visibility)
-- =============================================================================

drop policy if exists story_likes_hide_from_community on public.story_likes;
create policy story_likes_hide_from_community
  on public.story_likes as restrictive
  for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(user_id));

drop policy if exists story_views_hide_from_community on public.story_views;
create policy story_views_hide_from_community
  on public.story_views as restrictive
  for select to anon, authenticated
  using (public.profile_is_visible_to_viewer(viewer_id));