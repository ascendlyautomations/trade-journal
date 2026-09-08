-- TradeTraxs Vault — private saved content with user folders (V1).
-- Normalized: vault_items (one row per user+content) + vault_folders + vault_folder_items (M:N).
-- Quick Save = vault_item with zero folder rows. Removing a folder only drops folder membership.

-- =============================================================================
-- Tables
-- =============================================================================

create table if not exists public.vault_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  content_type text not null,
  content_id uuid not null,
  created_at timestamptz not null default now(),
  constraint vault_items_content_type_ck check (
    content_type in ('trade', 'profile_post', 'feed_post', 'reel', 'achievement')
  ),
  constraint vault_items_unique unique (user_id, content_type, content_id)
);

comment on table public.vault_items is
  'Private Vault saves — one row per viewer + content surface. Folders are optional via vault_folder_items.';

create index if not exists vault_items_user_created_at_idx
  on public.vault_items (user_id, created_at desc);

create index if not exists vault_items_user_type_created_at_idx
  on public.vault_items (user_id, content_type, created_at desc);

create table if not exists public.vault_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint vault_folders_name_trim_ck check (
    char_length(trim(name)) >= 1 and char_length(trim(name)) <= 64
  )
);

comment on table public.vault_folders is
  'User-created Vault folders — private organization only; never visible to other users.';

create unique index if not exists vault_folders_user_name_unique_idx
  on public.vault_folders (user_id, lower(trim(name)));

create index if not exists vault_folders_user_updated_at_idx
  on public.vault_folders (user_id, updated_at desc);

create table if not exists public.vault_folder_items (
  folder_id uuid not null references public.vault_folders (id) on delete cascade,
  vault_item_id uuid not null references public.vault_items (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (folder_id, vault_item_id)
);

comment on table public.vault_folder_items is
  'Optional folder membership for Vault items. Deleting a folder removes associations only.';

create index if not exists vault_folder_items_vault_item_id_idx
  on public.vault_folder_items (vault_item_id);

-- =============================================================================
-- RLS — owner-only; Vault is never readable by other users.
-- =============================================================================

alter table public.vault_items enable row level security;
alter table public.vault_folders enable row level security;
alter table public.vault_folder_items enable row level security;

drop policy if exists vault_items_select_own on public.vault_items;
drop policy if exists vault_items_insert_own on public.vault_items;
drop policy if exists vault_items_delete_own on public.vault_items;

create policy vault_items_select_own
  on public.vault_items
  for select
  to authenticated
  using (user_id = auth.uid());

create policy vault_items_insert_own
  on public.vault_items
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy vault_items_delete_own
  on public.vault_items
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists vault_folders_select_own on public.vault_folders;
drop policy if exists vault_folders_insert_own on public.vault_folders;
drop policy if exists vault_folders_update_own on public.vault_folders;
drop policy if exists vault_folders_delete_own on public.vault_folders;

create policy vault_folders_select_own
  on public.vault_folders
  for select
  to authenticated
  using (user_id = auth.uid());

create policy vault_folders_insert_own
  on public.vault_folders
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy vault_folders_update_own
  on public.vault_folders
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy vault_folders_delete_own
  on public.vault_folders
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists vault_folder_items_select_own on public.vault_folder_items;
drop policy if exists vault_folder_items_insert_own on public.vault_folder_items;
drop policy if exists vault_folder_items_delete_own on public.vault_folder_items;

create policy vault_folder_items_select_own
  on public.vault_folder_items
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.vault_folders vf
      where vf.id = vault_folder_items.folder_id
        and vf.user_id = auth.uid()
    )
  );

create policy vault_folder_items_insert_own
  on public.vault_folder_items
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.vault_folders vf
      join public.vault_items vi on vi.user_id = vf.user_id
      where vf.id = vault_folder_items.folder_id
        and vf.user_id = auth.uid()
        and vi.id = vault_folder_items.vault_item_id
        and vi.user_id = auth.uid()
    )
  );

create policy vault_folder_items_delete_own
  on public.vault_folder_items
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.vault_folders vf
      where vf.id = vault_folder_items.folder_id
        and vf.user_id = auth.uid()
    )
  );

revoke all on table public.vault_items from anon;
revoke all on table public.vault_folders from anon;
revoke all on table public.vault_folder_items from anon;

grant select, insert, delete on table public.vault_items to authenticated;
grant select, insert, update, delete on table public.vault_folders to authenticated;
grant select, insert, delete on table public.vault_folder_items to authenticated;

grant all on table public.vault_items to service_role;
grant all on table public.vault_folders to service_role;
grant all on table public.vault_folder_items to service_role;

-- =============================================================================
-- Batch vault-state lookup for Feed / lists (no N+1 per card).
-- =============================================================================

create or replace function public.rpc_v1_vault_state_batch(p_items jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    return '[]'::jsonb;
  end if;

  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'content_type', vi.content_type,
          'content_id', vi.content_id::text,
          'vault_item_id', vi.id::text,
          'folder_ids', coalesce(
            (
              select jsonb_agg(vf.id::text order by vf.name)
              from public.vault_folder_items vfi
              join public.vault_folders vf on vf.id = vfi.folder_id
              where vfi.vault_item_id = vi.id
                and vf.user_id = v_uid
            ),
            '[]'::jsonb
          )
        )
      )
      from public.vault_items vi
      where vi.user_id = v_uid
        and exists (
          select 1
          from jsonb_array_elements(p_items) elem
          where elem->>'content_type' = vi.content_type
            and (elem->>'content_id')::uuid = vi.content_id
        )
    ),
    '[]'::jsonb
  );
end;
$$;

comment on function public.rpc_v1_vault_state_batch(jsonb) is
  'Returns vaulted state for a batch of content refs — keyed by content_type + content_id.';

revoke all on function public.rpc_v1_vault_state_batch(jsonb) from public;
grant execute on function public.rpc_v1_vault_state_batch(jsonb) to authenticated;
