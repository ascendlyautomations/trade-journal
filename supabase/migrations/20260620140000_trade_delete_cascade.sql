-- Trade deletion hardening: cascade FKs + delete_own_trade RPC (RLS-safe cleanup).
--
-- AUDIT — tables referencing public.trades(id):
--   trade_likes.trade_id          — already ON DELETE CASCADE (20260406120000)
--   trade_comments.trade_id       — already ON DELETE CASCADE (20260406120000)
--   notifications.trade_id        — was SET NULL → CASCADE (this migration)
--   posts.trade_id                — FK added/updated → CASCADE (feed posts)
--   saved_trades.trade_id         — FK added/updated → CASCADE
--   messages.trade_id             — FK added/updated → CASCADE (DM trade shares)
--   room_messages.trade_id        — FK added/updated → CASCADE (room trade shares)
--   room_messages.pinned_trade_id — FK added/updated → SET NULL (keep message, drop pin)
--
-- Cascades from posts.trade_id (feed engagement):
--   likes.post_id, comments.post_id, saved_posts.post_id, notifications.post_id
--
-- Manual cleanup in delete_own_trade() (RLS bypass via SECURITY DEFINER):
--   All rows above, plus message_likes/message_comments on trade-share messages.

create or replace function public._replace_fk_to_trades(
  p_table text,
  p_column text,
  p_on_delete text
)
returns void
language plpgsql
as $$
declare
  v_conname text;
  v_new_name text;
begin
  select c.conname
  into v_conname
  from pg_constraint c
  join pg_class t on c.conrelid = t.oid
  join pg_namespace n on t.relnamespace = n.oid
  join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
  where n.nspname = 'public'
    and t.relname = p_table
    and c.contype = 'f'
    and c.confrelid = 'public.trades'::regclass
    and a.attname = p_column
  limit 1;

  if v_conname is not null then
    execute format(
      'alter table public.%I drop constraint %I',
      p_table,
      v_conname
    );
  end if;

  v_new_name := p_table || '_' || p_column || '_fkey';

  execute format(
    'alter table public.%I add constraint %I foreign key (%I) references public.trades(id) on delete %s',
    p_table,
    v_new_name,
    p_column,
    p_on_delete
  );
exception
  when duplicate_object then
    null;
end;
$$;

create or replace function public._replace_fk_to_posts(
  p_table text,
  p_column text default 'post_id'
)
returns void
language plpgsql
as $$
declare
  v_conname text;
  v_new_name text;
begin
  select c.conname
  into v_conname
  from pg_constraint c
  join pg_class t on c.conrelid = t.oid
  join pg_namespace n on t.relnamespace = n.oid
  join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
  where n.nspname = 'public'
    and t.relname = p_table
    and c.contype = 'f'
    and c.confrelid = 'public.posts'::regclass
    and a.attname = p_column
  limit 1;

  if v_conname is not null then
    execute format(
      'alter table public.%I drop constraint %I',
      p_table,
      v_conname
    );
  end if;

  v_new_name := p_table || '_' || p_column || '_fkey';

  execute format(
    'alter table public.%I add constraint %I foreign key (%I) references public.posts(id) on delete cascade',
    p_table,
    v_new_name,
    p_column
  );
exception
  when duplicate_object then
    null;
  when undefined_table then
    null;
end;
$$;

-- Feed post FK (one post per trade).
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'posts'
      and column_name = 'trade_id'
  ) then
    perform public._replace_fk_to_trades('posts', 'trade_id', 'cascade');
  end if;
end;
$$;

-- Engagement / notifications / shares
do $$
begin
  if to_regclass('public.notifications') is not null then
    perform public._replace_fk_to_trades('notifications', 'trade_id', 'cascade');
  end if;

  if to_regclass('public.saved_trades') is not null then
    perform public._replace_fk_to_trades('saved_trades', 'trade_id', 'cascade');
  end if;

  if to_regclass('public.messages') is not null then
    perform public._replace_fk_to_trades('messages', 'trade_id', 'cascade');
  end if;

  if to_regclass('public.room_messages') is not null then
    perform public._replace_fk_to_trades('room_messages', 'trade_id', 'cascade');
    perform public._replace_fk_to_trades('room_messages', 'pinned_trade_id', 'set null');
  end if;
end;
$$;

-- Feed post engagement cascades when posts row is removed.
do $$
begin
  if to_regclass('public.likes') is not null then
    perform public._replace_fk_to_posts('likes');
  end if;

  if to_regclass('public.comments') is not null then
    perform public._replace_fk_to_posts('comments');
  end if;

  if to_regclass('public.saved_posts') is not null then
    perform public._replace_fk_to_posts('saved_posts');
  end if;

  if to_regclass('public.notifications') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema = 'public'
         and table_name = 'notifications'
         and column_name = 'post_id'
     ) then
    perform public._replace_fk_to_posts('notifications', 'post_id');
  end if;
end;
$$;

-- Owner-initiated delete (bypasses RLS on child engagement rows).
create or replace function public.delete_own_trade(p_trade_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_post_ids uuid[];
  v_message_ids uuid[];
begin
  if p_trade_id is null then
    raise exception 'Trade id is required';
  end if;

  select user_id into v_owner
  from public.trades
  where id = p_trade_id;

  if v_owner is null then
    raise exception 'Trade not found';
  end if;

  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if v_owner is distinct from auth.uid() then
    raise exception 'Not authorized to delete this trade';
  end if;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_post_ids
  from public.posts
  where trade_id = p_trade_id;

  if coalesce(array_length(v_post_ids, 1), 0) > 0 then
    delete from public.likes where post_id = any (v_post_ids);
    delete from public.comments where post_id = any (v_post_ids);

    if to_regclass('public.saved_posts') is not null then
      delete from public.saved_posts where post_id = any (v_post_ids);
    end if;

    delete from public.notifications where post_id = any (v_post_ids);
    delete from public.posts where id = any (v_post_ids);
  end if;

  delete from public.notifications where trade_id = p_trade_id;
  delete from public.trade_likes where trade_id = p_trade_id;
  delete from public.trade_comments where trade_id = p_trade_id;

  if to_regclass('public.saved_trades') is not null then
    delete from public.saved_trades where trade_id = p_trade_id;
  end if;

  select coalesce(array_agg(id), '{}'::uuid[])
  into v_message_ids
  from public.messages
  where trade_id = p_trade_id;

  if coalesce(array_length(v_message_ids, 1), 0) > 0 then
    if to_regclass('public.message_likes') is not null then
      delete from public.message_likes where message_id = any (v_message_ids);
    end if;

    if to_regclass('public.message_comments') is not null then
      delete from public.message_comments where message_id = any (v_message_ids);
    end if;

    delete from public.messages where id = any (v_message_ids);
  end if;

  if to_regclass('public.room_messages') is not null then
    delete from public.room_messages where trade_id = p_trade_id;
    update public.room_messages
    set pinned_trade_id = null
    where pinned_trade_id = p_trade_id;
  end if;

  delete from public.trades where id = p_trade_id;
end;
$$;

comment on function public.delete_own_trade(uuid) is
  'Deletes a trade owned by auth.uid() and all dependent feed, engagement, notification, and share records.';

grant execute on function public.delete_own_trade(uuid) to authenticated;

drop function if exists public._replace_fk_to_trades(text, text, text);
drop function if exists public._replace_fk_to_posts(text, text);
