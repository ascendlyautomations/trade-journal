-- Notification snapshot when retained story metadata is purged (trigger on stories DELETE).

do $verify$
declare
  fn text;
begin
  select pg_get_functiondef(p.oid)
    into fn
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'stories_preserve_like_notifications';

  if fn is null then
    raise exception 'verify: stories_preserve_like_notifications missing';
  end if;

  if fn not like '%story_unavailable%' then
    raise exception 'verify: preserve trigger must set story_unavailable in content';
  end if;

  if fn not like '%n.story_id = old.id%' then
    raise exception 'verify: preserve trigger must target like notifications for deleted story';
  end if;
end
$verify$;