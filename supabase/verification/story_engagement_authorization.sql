-- Story engagement authorization smoke checks (run against a migrated database).
-- Ensures RLS primitives and RPC grants exist; not a full pgTAP suite.

do $verify$
declare
  def text;
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_story_insights'
  ) then
    raise exception 'verify: rpc_v1_story_insights missing';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_story_record_view'
  ) then
    raise exception 'verify: rpc_v1_story_record_view missing';
  end if;

  if not exists (
    select 1
    from pg_tables
    where schemaname = 'public'
      and tablename = 'story_likes'
  ) then
    raise exception 'verify: story_likes table missing';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'story_likes'
      and policyname = 'story_likes_select_own'
  ) then
    raise exception 'verify: story_likes_select_own policy missing';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'story_views'
      and policyname like '%select%'
      and roles::text like '%authenticated%'
  ) then
    raise exception 'verify: story_views must not expose broad SELECT';
  end if;

  if not exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'notifications_like_story_unique_idx'
  ) then
    raise exception 'verify: notifications_like_story_unique_idx missing';
  end if;

  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_activity_bootstrap';

  if def is null then
    raise exception 'verify: rpc_v1_activity_bootstrap missing';
  end if;

  if def not like '%story_id%' then
    raise exception 'verify: rpc_v1_activity_bootstrap must project story_id';
  end if;

  if def not like '%guest_session_is_read_only()%' then
    raise exception 'verify: rpc_v1_activity_bootstrap must retain guest read-only guard';
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'story_likes'
  ) then
    raise exception 'verify: story_likes must be in supabase_realtime publication';
  end if;

  select pg_get_functiondef(p.oid)
    into def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_story_insights';

  if def is null then
    raise exception 'verify: rpc_v1_story_insights missing (function body)';
  end if;

  if def not like '%reply_count%' then
    raise exception 'verify: rpc_v1_story_insights must expose reply_count';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'stories'
      and t.tgname = 'stories_preserve_like_notifications'
  ) then
    raise exception 'verify: stories_preserve_like_notifications trigger missing';
  end if;
end
$verify$;