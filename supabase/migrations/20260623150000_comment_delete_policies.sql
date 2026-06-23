-- Allow authors to delete their own feed/trade comments.
-- Cascade-delete direct reply comments when a parent comment is removed.

do $$
begin
  if to_regclass('public.comments') is not null then
    alter table public.comments enable row level security;

    grant select, insert, delete on table public.comments to authenticated;

    drop policy if exists comments_delete_own on public.comments;
    create policy comments_delete_own
      on public.comments
      for delete
      to authenticated
      using (auth.uid() = user_id);

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'comments'
        and column_name = 'parent_comment_id'
    ) then
      alter table public.comments
        drop constraint if exists comments_parent_comment_id_fkey;

      alter table public.comments
        add constraint comments_parent_comment_id_fkey
        foreign key (parent_comment_id)
        references public.comments (id)
        on delete cascade;
    end if;
  end if;
end $$;

do $$
begin
  if to_regclass('public.trade_comments') is not null then
    alter table public.trade_comments enable row level security;

    grant select, insert, delete on table public.trade_comments to authenticated;

    drop policy if exists trade_comments_delete_own on public.trade_comments;
    create policy trade_comments_delete_own
      on public.trade_comments
      for delete
      to authenticated
      using (auth.uid() = user_id);

    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'trade_comments'
        and column_name = 'parent_comment_id'
    ) then
      alter table public.trade_comments
        drop constraint if exists trade_comments_parent_comment_id_fkey;

      alter table public.trade_comments
        add constraint trade_comments_parent_comment_id_fkey
        foreign key (parent_comment_id)
        references public.trade_comments (id)
        on delete cascade;
    end if;
  end if;
end $$;
