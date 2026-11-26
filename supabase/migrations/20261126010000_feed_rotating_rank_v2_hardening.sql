-- Rotating feed v2.1 hardening (idempotent). rpc_v1 untouched.
-- Requires 015 + 030 (_feed_rotating_v2_install_from_v1).

-- Post-deploy hardening for rotating feed (v2.1). rpc_v1 untouched.

-- Impression SELECT (idempotent for DBs that applied 015 before SELECT policy).
do $pol$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'feed_content_impressions'
      and policyname = 'feed_content_impressions_select_own'
  ) then
    create policy feed_content_impressions_select_own
      on public.feed_content_impressions
      for select
      to authenticated
      using (viewer_id = auth.uid());
  end if;
end $pol$;

grant select on table public.feed_content_impressions to authenticated;

create or replace function public._v2_feed_effective_impressed_at(
  p_last_impressed_at timestamptz,
  p_first_impressed_at timestamptz,
  p_rank_frozen_at timestamptz
)
returns timestamptz
language sql
immutable
as $$
  select case
    when p_last_impressed_at is null or p_first_impressed_at is null then null::timestamptz
    when p_last_impressed_at <= p_rank_frozen_at then p_last_impressed_at
    when p_first_impressed_at < p_rank_frozen_at then p_rank_frozen_at - interval '1 microsecond'
    else null::timestamptz
  end;
$$;

revoke all on function public._v2_feed_effective_impressed_at(timestamptz, timestamptz, timestamptz) from public;
grant execute on function public._v2_feed_effective_impressed_at(timestamptz, timestamptz, timestamptz) to authenticated;

create or replace function public._v2_feed_purge_impressions_for_content()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  delete from public.feed_content_impressions
  where content_kind = TG_ARGV[0]
    and content_id = old.id;
  return old;
end;
$$;

drop trigger if exists feed_impressions_purge_post on public.posts;
create trigger feed_impressions_purge_post
  after delete on public.posts
  for each row execute function public._v2_feed_purge_impressions_for_content('post');

drop trigger if exists feed_impressions_purge_profile_post on public.profile_posts;
create trigger feed_impressions_purge_profile_post
  after delete on public.profile_posts
  for each row execute function public._v2_feed_purge_impressions_for_content('profile_post');

drop trigger if exists feed_impressions_purge_achievement_post on public.achievement_posts;
create trigger feed_impressions_purge_achievement_post
  after delete on public.achievement_posts
  for each row execute function public._v2_feed_purge_impressions_for_content('achievement_post');

drop trigger if exists feed_impressions_purge_reel on public.reels;
create trigger feed_impressions_purge_reel
  after delete on public.reels
  for each row execute function public._v2_feed_purge_impressions_for_content('reel');

-- Legacy exclude-keys overload only (do not drop current 7-arg v2).
drop function if exists public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text[]);

select public._feed_rotating_v2_install_from_v1();

do $comment$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'rpc_v2_feed_bootstrap' and p.pronargs = 7
  ) then
    execute $cmd$
      comment on function public.rpc_v2_feed_bootstrap(text, text, integer, text, text, timestamptz, text) is
        'Rotating feed bootstrap — rank + chrono scan cursors, frozen impression snapshot. v1 unchanged.'
    $cmd$;
  end if;
end
$comment$;
