-- Pinned comments: one pinned top-level comment per parent content item.
-- Only the content owner may toggle `pinned` (comment authors cannot pin on others' content).

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.comments') is not null then
    alter table public.comments
      add column if not exists pinned boolean not null default false;
  end if;

  if to_regclass('public.trade_comments') is not null then
    alter table public.trade_comments
      add column if not exists pinned boolean not null default false;
  end if;

  if to_regclass('public.profile_post_comments') is not null then
    alter table public.profile_post_comments
      add column if not exists pinned boolean not null default false;
  end if;

  if to_regclass('public.reel_comments') is not null then
    alter table public.reel_comments
      add column if not exists pinned boolean not null default false;
  end if;

  if to_regclass('public.achievement_post_comments') is not null then
    alter table public.achievement_post_comments
      add column if not exists pinned boolean not null default false;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Unique: at most one pinned top-level comment per parent
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.comments') is not null then
    create unique index if not exists comments_one_pinned_per_post
      on public.comments (post_id)
      where pinned = true and parent_comment_id is null;
  end if;

  if to_regclass('public.trade_comments') is not null then
    create unique index if not exists trade_comments_one_pinned_per_trade
      on public.trade_comments (trade_id)
      where pinned = true and parent_comment_id is null;
  end if;

  if to_regclass('public.profile_post_comments') is not null then
    create unique index if not exists profile_post_comments_one_pinned_per_post
      on public.profile_post_comments (profile_post_id)
      where pinned = true and parent_comment_id is null;
  end if;

  if to_regclass('public.reel_comments') is not null then
    create unique index if not exists reel_comments_one_pinned_per_reel
      on public.reel_comments (reel_id)
      where pinned = true and parent_comment_id is null;
  end if;

  if to_regclass('public.achievement_post_comments') is not null then
    create unique index if not exists achievement_post_comments_one_pinned_per_post
      on public.achievement_post_comments (achievement_post_id)
      where pinned = true and parent_comment_id is null;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Guard + exclusive pin (unpin prior sibling when pinning)
-- ---------------------------------------------------------------------------
create or replace function public.comments_enforce_pinned_rules()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  -- Only the `pinned` column may change under pin UPDATE policies.
  if tg_op = 'UPDATE'
     and (to_jsonb(new) - 'pinned') is distinct from (to_jsonb(old) - 'pinned') then
    raise exception 'Only the pinned flag may be updated on comments.';
  end if;

  if new.pinned = true then
    if new.parent_comment_id is not null then
      raise exception 'Only top-level comments can be pinned.';
    end if;

    if tg_table_name = 'comments' then
      update public.comments
         set pinned = false
       where post_id = new.post_id
         and id is distinct from new.id
         and pinned = true;
    elsif tg_table_name = 'trade_comments' then
      update public.trade_comments
         set pinned = false
       where trade_id = new.trade_id
         and id is distinct from new.id
         and pinned = true;
    elsif tg_table_name = 'profile_post_comments' then
      update public.profile_post_comments
         set pinned = false
       where profile_post_id = new.profile_post_id
         and id is distinct from new.id
         and pinned = true;
    elsif tg_table_name = 'reel_comments' then
      update public.reel_comments
         set pinned = false
       where reel_id = new.reel_id
         and id is distinct from new.id
         and pinned = true;
    elsif tg_table_name = 'achievement_post_comments' then
      update public.achievement_post_comments
         set pinned = false
       where achievement_post_id = new.achievement_post_id
         and id is distinct from new.id
         and pinned = true;
    end if;
  end if;

  return new;
end;
$$;

do $$
begin
  if to_regclass('public.comments') is not null then
    drop trigger if exists comments_enforce_pinned_rules_trg on public.comments;
    create trigger comments_enforce_pinned_rules_trg
      before update of pinned on public.comments
      for each row
      execute function public.comments_enforce_pinned_rules();
  end if;

  if to_regclass('public.trade_comments') is not null then
    drop trigger if exists trade_comments_enforce_pinned_rules_trg on public.trade_comments;
    create trigger trade_comments_enforce_pinned_rules_trg
      before update of pinned on public.trade_comments
      for each row
      execute function public.comments_enforce_pinned_rules();
  end if;

  if to_regclass('public.profile_post_comments') is not null then
    drop trigger if exists profile_post_comments_enforce_pinned_rules_trg
      on public.profile_post_comments;
    create trigger profile_post_comments_enforce_pinned_rules_trg
      before update of pinned on public.profile_post_comments
      for each row
      execute function public.comments_enforce_pinned_rules();
  end if;

  if to_regclass('public.reel_comments') is not null then
    drop trigger if exists reel_comments_enforce_pinned_rules_trg on public.reel_comments;
    create trigger reel_comments_enforce_pinned_rules_trg
      before update of pinned on public.reel_comments
      for each row
      execute function public.comments_enforce_pinned_rules();
  end if;

  if to_regclass('public.achievement_post_comments') is not null then
    drop trigger if exists achievement_post_comments_enforce_pinned_rules_trg
      on public.achievement_post_comments;
    create trigger achievement_post_comments_enforce_pinned_rules_trg
      before update of pinned on public.achievement_post_comments
      for each row
      execute function public.comments_enforce_pinned_rules();
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Grants + RLS: content owner may UPDATE (pin/unpin only; enforced by trigger)
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.comments') is not null then
    grant select, insert, update, delete on table public.comments to authenticated;

    drop policy if exists comments_update_pinned_by_content_owner on public.comments;
    create policy comments_update_pinned_by_content_owner
      on public.comments
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.posts p
          where p.id = comments.post_id
            and p.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.posts p
          where p.id = comments.post_id
            and p.user_id = auth.uid()
        )
      );
  end if;

  if to_regclass('public.trade_comments') is not null then
    grant select, insert, update, delete on table public.trade_comments to authenticated;

    drop policy if exists trade_comments_update_pinned_by_content_owner
      on public.trade_comments;
    create policy trade_comments_update_pinned_by_content_owner
      on public.trade_comments
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.trades t
          where t.id = trade_comments.trade_id
            and t.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.trades t
          where t.id = trade_comments.trade_id
            and t.user_id = auth.uid()
        )
      );
  end if;

  if to_regclass('public.profile_post_comments') is not null then
    grant select, insert, update, delete
      on table public.profile_post_comments to authenticated;

    drop policy if exists profile_post_comments_update_pinned_by_content_owner
      on public.profile_post_comments;
    create policy profile_post_comments_update_pinned_by_content_owner
      on public.profile_post_comments
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.profile_posts pp
          where pp.id = profile_post_comments.profile_post_id
            and pp.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.profile_posts pp
          where pp.id = profile_post_comments.profile_post_id
            and pp.user_id = auth.uid()
        )
      );
  end if;

  if to_regclass('public.reel_comments') is not null then
    grant select, insert, update, delete on table public.reel_comments to authenticated;

    drop policy if exists reel_comments_update_pinned_by_content_owner
      on public.reel_comments;
    create policy reel_comments_update_pinned_by_content_owner
      on public.reel_comments
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.reels r
          where r.id = reel_comments.reel_id
            and r.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.reels r
          where r.id = reel_comments.reel_id
            and r.user_id = auth.uid()
        )
      );
  end if;

  if to_regclass('public.achievement_post_comments') is not null then
    grant select, insert, update, delete
      on table public.achievement_post_comments to authenticated;

    drop policy if exists achievement_post_comments_update_pinned_by_content_owner
      on public.achievement_post_comments;
    create policy achievement_post_comments_update_pinned_by_content_owner
      on public.achievement_post_comments
      for update
      to authenticated
      using (
        exists (
          select 1
          from public.achievement_posts ap
          where ap.id = achievement_post_comments.achievement_post_id
            and ap.user_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1
          from public.achievement_posts ap
          where ap.id = achievement_post_comments.achievement_post_id
            and ap.user_id = auth.uid()
        )
      );
  end if;
end $$;

-- Realtime: pin flips should stream to open comment UIs
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if to_regclass('public.comments') is not null then
      begin
        alter publication supabase_realtime add table public.comments;
      exception when duplicate_object then null;
      end;
      alter table public.comments replica identity full;
    end if;

    if to_regclass('public.trade_comments') is not null then
      begin
        alter publication supabase_realtime add table public.trade_comments;
      exception when duplicate_object then null;
      end;
      alter table public.trade_comments replica identity full;
    end if;

    if to_regclass('public.profile_post_comments') is not null then
      begin
        alter publication supabase_realtime add table public.profile_post_comments;
      exception when duplicate_object then null;
      end;
      alter table public.profile_post_comments replica identity full;
    end if;

    if to_regclass('public.reel_comments') is not null then
      begin
        alter publication supabase_realtime add table public.reel_comments;
      exception when duplicate_object then null;
      end;
      alter table public.reel_comments replica identity full;
    end if;

    if to_regclass('public.achievement_post_comments') is not null then
      begin
        alter publication supabase_realtime add table public.achievement_post_comments;
      exception when duplicate_object then null;
      end;
      alter table public.achievement_post_comments replica identity full;
    end if;
  end if;
end $$;
