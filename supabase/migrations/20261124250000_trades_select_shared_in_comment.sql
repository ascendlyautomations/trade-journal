-- Private trade sharing via social comment attachments (comment-scoped read via RLS).
-- Prerequisite: 20261124220000_comment_shared_trade_attachment.sql
--               20260609220000_trades_select_shared_in_conversation.sql
--
-- Visibility: authenticated users may read trades referenced by shared_trade_id on comment
-- rows they can already SELECT (comment RLS + hide_from_community). Does not set is_public.
-- FK ON DELETE SET NULL revokes access when the attached trade is deleted; deleting the
-- comment row removes the grant unless another valid share (DM, room, comment) exists.

-- =============================================================================
-- 1. INSERT guard — only the trade owner may attach owned trades
-- =============================================================================

create or replace function public.comments_assert_shared_trade_owned(p_shared_trade_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if p_shared_trade_id is null then
    return;
  end if;

  if auth.uid() is null then
    raise exception 'shared trade attachment requires authentication'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.trades t
    where t.id = p_shared_trade_id
      and t.user_id = auth.uid()
  ) then
    raise exception 'you can only attach trades you own'
      using errcode = '42501';
  end if;
end;
$$;

comment on function public.comments_assert_shared_trade_owned(uuid) is
  'Raises when shared_trade_id is set by a non-owner (all comment attachment tables).';

create or replace function public.comments_before_insert_shared_trade_guard()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  perform public.comments_assert_shared_trade_owned(new.shared_trade_id);
  return new;
end;
$$;

-- comments (feed posts)
drop trigger if exists comments_before_insert_shared_trade_guard on public.comments;
create trigger comments_before_insert_shared_trade_guard
  before insert on public.comments
  for each row
  execute function public.comments_before_insert_shared_trade_guard();

-- trade_comments
drop trigger if exists trade_comments_before_insert_shared_trade_guard on public.trade_comments;
create trigger trade_comments_before_insert_shared_trade_guard
  before insert on public.trade_comments
  for each row
  execute function public.comments_before_insert_shared_trade_guard();

-- profile_post_comments
drop trigger if exists profile_post_comments_before_insert_shared_trade_guard on public.profile_post_comments;
create trigger profile_post_comments_before_insert_shared_trade_guard
  before insert on public.profile_post_comments
  for each row
  execute function public.comments_before_insert_shared_trade_guard();

-- achievement_post_comments
drop trigger if exists achievement_post_comments_before_insert_shared_trade_guard on public.achievement_post_comments;
create trigger achievement_post_comments_before_insert_shared_trade_guard
  before insert on public.achievement_post_comments
  for each row
  execute function public.comments_before_insert_shared_trade_guard();

-- reel_comments
drop trigger if exists reel_comments_before_insert_shared_trade_guard on public.reel_comments;
create trigger reel_comments_before_insert_shared_trade_guard
  before insert on public.reel_comments
  for each row
  execute function public.comments_before_insert_shared_trade_guard();

-- =============================================================================
-- 2. SELECT — comment-scoped private trade read (OR policy on public.trades)
-- =============================================================================

drop policy if exists "trades_select_shared_in_comment" on public.trades;

create policy "trades_select_shared_in_comment"
  on public.trades
  for select
  to authenticated
  using (
  exists (
    select 1
    from public.comments c
    where c.shared_trade_id = trades.id
  )
  or exists (
    select 1
    from public.trade_comments tc
    where tc.shared_trade_id = trades.id
  )
  or exists (
    select 1
    from public.profile_post_comments ppc
    where ppc.shared_trade_id = trades.id
  )
  or exists (
    select 1
    from public.achievement_post_comments apc
    where apc.shared_trade_id = trades.id
  )
  or exists (
    select 1
    from public.reel_comments rc
    where rc.shared_trade_id = trades.id
  )
  );

comment on policy "trades_select_shared_in_comment" on public.trades is
  'Authenticated users may read trades attached to social comments they can read via comment RLS.';

-- =============================================================================
-- ROLLBACK (manual)
-- =============================================================================
-- drop policy if exists "trades_select_shared_in_comment" on public.trades;
-- drop trigger if exists reel_comments_before_insert_shared_trade_guard on public.reel_comments;
-- drop trigger if exists achievement_post_comments_before_insert_shared_trade_guard on public.achievement_post_comments;
-- drop trigger if exists profile_post_comments_before_insert_shared_trade_guard on public.profile_post_comments;
-- drop trigger if exists trade_comments_before_insert_shared_trade_guard on public.trade_comments;
-- drop trigger if exists comments_before_insert_shared_trade_guard on public.comments;
-- drop function if exists public.comments_before_insert_shared_trade_guard();
-- drop function if exists public.comments_assert_shared_trade_owned(uuid);