-- Phase 3 Disk IO: reduce rate-limit write amplification + close comment-delete
-- notification sync gaps. Enforcement limits and notification delivery unchanged.

-- ---------------------------------------------------------------------------
-- 1. Drop leftover shadow follow@60 rule (beta_launch never retuned it; binding
--    limits are follow@3600=30 and follow@86400=200). Removes one counter write
--    per follow without changing effective production caps.
-- ---------------------------------------------------------------------------
delete from public.rate_limit_rules
where action = 'follow'
  and window_seconds = 60;

-- ---------------------------------------------------------------------------
-- 2. Collapse N per-window counter upserts into one bundle row per action hit.
--    Window floors and max_count checks match the prior loop. Over-limit hits
--    still persist the incremented counts then raise (same as before).
-- ---------------------------------------------------------------------------

alter table public.rate_limit_counters
  add column if not exists windows jsonb not null default '{}'::jsonb;

create or replace function public.rate_limit_hit(p_action text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_rule record;
  v_window_start timestamptz;
  v_now timestamptz := now();
  v_bundle jsonb := '{}'::jsonb;
  v_entry jsonb;
  v_count integer;
  v_bundle_start timestamptz := to_timestamp(0);
  v_any_rule boolean := false;
  v_exceeded boolean := false;
begin
  if public.rate_limit_is_service_role() then
    return;
  end if;

  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'rate_limit_not_authenticated'
      using errcode = 'P0001';
  end if;

  if p_action is null or btrim(p_action) = '' then
    raise exception 'rate_limit_invalid_action'
      using errcode = 'P0001';
  end if;

  select c.windows
    into v_bundle
  from public.rate_limit_counters c
  where c.user_id = v_user_id
    and c.action = p_action
    and c.window_seconds = 0
    and c.window_start = v_bundle_start;

  if v_bundle is null then
    v_bundle := '{}'::jsonb;

    -- Seed once from legacy per-window rows for the active window floors.
    for v_rule in
      select r.window_seconds
      from public.rate_limit_rules r
      where r.action = p_action
    loop
      v_window_start := to_timestamp(
        floor(extract(epoch from v_now) / v_rule.window_seconds) * v_rule.window_seconds
      );
      select c.count
        into v_count
      from public.rate_limit_counters c
      where c.user_id = v_user_id
        and c.action = p_action
        and c.window_seconds = v_rule.window_seconds
        and c.window_start = v_window_start;
      if found then
        v_bundle := jsonb_set(
          v_bundle,
          array[v_rule.window_seconds::text],
          jsonb_build_object(
            'start', v_window_start,
            'count', v_count
          ),
          true
        );
      end if;
    end loop;
  end if;

  for v_rule in
    select r.window_seconds, r.max_count
    from public.rate_limit_rules r
    where r.action = p_action
    order by r.window_seconds
  loop
    v_any_rule := true;
    v_window_start := to_timestamp(
      floor(extract(epoch from v_now) / v_rule.window_seconds) * v_rule.window_seconds
    );

    v_entry := v_bundle -> v_rule.window_seconds::text;
    if v_entry is null
       or (v_entry ->> 'start')::timestamptz is distinct from v_window_start then
      v_count := 1;
    else
      v_count := coalesce((v_entry ->> 'count')::integer, 0) + 1;
    end if;

    if v_count > v_rule.max_count then
      v_exceeded := true;
    end if;

    v_bundle := jsonb_set(
      v_bundle,
      array[v_rule.window_seconds::text],
      jsonb_build_object(
        'start', v_window_start,
        'count', v_count
      ),
      true
    );
  end loop;

  if not v_any_rule then
    return;
  end if;

  insert into public.rate_limit_counters (
    user_id,
    action,
    window_seconds,
    window_start,
    count,
    windows
  )
  values (
    v_user_id,
    p_action,
    0,
    v_bundle_start,
    1,
    v_bundle
  )
  on conflict (user_id, action, window_seconds, window_start)
  do update
    set windows = excluded.windows,
        count = public.rate_limit_counters.count + 1;

  if v_exceeded then
    raise exception 'rate_limit_exceeded:%', p_action
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function public.rate_limit_hit(text) is
  'Increment all windows for action/user in one counter row; raise rate_limit_exceeded:{action} when over limit.';

-- Preserve bundle rows during ops cleanup (window_start is epoch 0).
create or replace function public.rate_limit_cleanup_counters(
  p_retain interval default interval '48 hours'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer;
begin
  delete from public.rate_limit_counters
  where window_seconds <> 0
    and window_start < now() - p_retain;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Comment notification sync-delete on reel + achievement comments
--    (matches comments / trade_comments / profile_post_comments)
-- ---------------------------------------------------------------------------
drop trigger if exists reel_comments_sync_delete_comment_notification
  on public.reel_comments;
create trigger reel_comments_sync_delete_comment_notification
  after delete on public.reel_comments
  for each row
  execute function public.sync_delete_comment_notification();

drop trigger if exists achievement_post_comments_sync_delete_comment_notification
  on public.achievement_post_comments;
create trigger achievement_post_comments_sync_delete_comment_notification
  after delete on public.achievement_post_comments
  for each row
  execute function public.sync_delete_comment_notification();
