-- Public trading-account insights: dropdown visibility, custom status, manual payouts.
-- Safe public exposure is RPC-whitelisted only (never raw accounts rows to anon/other users).
--
-- Security model:
--   • public.accounts — unchanged authorization; no new/changed RLS policies here.
--   • public.account_payout_entries — owner-only CRUD via RLS (not publicly readable).
--   • public.rpc_v1_profile_account_insights — SECURITY DEFINER read gateway with
--     profile privacy / follower / block checks; whitelisted JSON only.

-- ---------------------------------------------------------------------------
-- accounts: dropdown visibility + optional public status label
-- (columns only — preserve existing production RLS/grants)
-- ---------------------------------------------------------------------------

alter table public.accounts
  add column if not exists show_in_account_dropdowns boolean not null default true;

alter table public.accounts
  add column if not exists custom_public_status text null;

alter table public.accounts
  drop constraint if exists accounts_custom_public_status_length_chk;

alter table public.accounts
  add constraint accounts_custom_public_status_length_chk
  check (
    custom_public_status is null
    or (
      char_length(trim(custom_public_status)) between 1 and 32
    )
  );

create or replace function public.accounts_normalize_custom_public_status()
returns trigger
language plpgsql
as $$
begin
  if new.custom_public_status is not null then
    new.custom_public_status := nullif(trim(new.custom_public_status), '');
  end if;
  return new;
end;
$$;

drop trigger if exists accounts_normalize_custom_public_status on public.accounts;
create trigger accounts_normalize_custom_public_status
  before insert or update of custom_public_status on public.accounts
  for each row
  execute function public.accounts_normalize_custom_public_status();

comment on column public.accounts.show_in_account_dropdowns is
  'When false, account stays in Manage Accounts and history but is hidden from trade/account pickers.';
comment on column public.accounts.custom_public_status is
  'Optional owner-defined public label (e.g. Blown, Passed, Funded). Blank normalizes to NULL.';

-- ---------------------------------------------------------------------------
-- account_payout_entries: owner-managed manual payout log (public via RPC only)
-- ---------------------------------------------------------------------------

create table if not exists public.account_payout_entries (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  amount numeric(14, 2) not null,
  payout_date date not null,
  note text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint account_payout_entries_amount_positive check (amount > 0),
  constraint account_payout_entries_note_length check (
    note is null or char_length(trim(note)) <= 120
  )
);

create index if not exists account_payout_entries_account_id_idx
  on public.account_payout_entries (account_id, payout_date desc, id desc);

create index if not exists account_payout_entries_user_id_idx
  on public.account_payout_entries (user_id, payout_date desc);

create or replace function public.account_payout_entries_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if new.note is not null then
    new.note := nullif(trim(new.note), '');
  end if;
  return new;
end;
$$;

drop trigger if exists account_payout_entries_set_updated_at on public.account_payout_entries;
create trigger account_payout_entries_set_updated_at
  before insert or update on public.account_payout_entries
  for each row
  execute function public.account_payout_entries_set_updated_at();

alter table public.account_payout_entries enable row level security;

drop policy if exists "account_payout_entries_select_own" on public.account_payout_entries;
create policy "account_payout_entries_select_own"
  on public.account_payout_entries
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "account_payout_entries_insert_own" on public.account_payout_entries;
create policy "account_payout_entries_insert_own"
  on public.account_payout_entries
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.accounts a
      where a.id = account_id
        and a.user_id = auth.uid()
    )
  );

drop policy if exists "account_payout_entries_update_own" on public.account_payout_entries;
create policy "account_payout_entries_update_own"
  on public.account_payout_entries
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.accounts a
      where a.id = account_id
        and a.user_id = auth.uid()
    )
  );

drop policy if exists "account_payout_entries_delete_own" on public.account_payout_entries;
create policy "account_payout_entries_delete_own"
  on public.account_payout_entries
  for delete
  to authenticated
  using (user_id = auth.uid());

revoke all on table public.account_payout_entries from anon, authenticated;
grant select, insert, update, delete on table public.account_payout_entries to authenticated;

-- Realtime: owner payout edits refresh Manage Accounts / profile caches.
-- Do not re-add accounts if already published (avoid duplicate_object noise).
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    return;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'account_payout_entries'
  ) then
    alter publication supabase_realtime add table public.account_payout_entries;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Public profile contract — whitelisted fields only (SECURITY DEFINER gateway)
-- ---------------------------------------------------------------------------
-- Justification: accounts and account_payout_entries remain owner-readable via RLS.
-- Public profile viewers (including anon) must not receive direct table SELECT.
-- This function mirrors rpc_v1_profile_bootstrap privacy gates, then reads base
-- tables as definer ONLY after v_can_view is true. Read-only; no mutations.

create or replace function public.rpc_v1_profile_account_insights(p_identifier text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_viewer uuid := auth.uid();
  v_profile_id uuid;
  v_profile public.profiles%rowtype;
  v_is_own boolean := false;
  v_is_following boolean := false;
  v_can_view boolean := false;
  v_accounts jsonb := '[]'::jsonb;
begin
  if p_identifier is null or trim(p_identifier) = '' then
    raise exception 'invalid_identifier' using errcode = '22023';
  end if;

  if p_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select * into v_profile
    from public.profiles p
    where p.id = p_identifier::uuid;
  else
    select * into v_profile
    from public.profiles p
    where lower(trim(p.username)) = lower(trim(p_identifier));
  end if;

  if v_profile.id is null then
    return jsonb_build_object(
      'meta', jsonb_build_object('contract_version', 1, 'found', false),
      'data', jsonb_build_object('accounts', '[]'::jsonb)
    );
  end if;

  v_profile_id := v_profile.id;
  v_is_own := v_viewer is not null and v_viewer = v_profile_id;

  if v_viewer is not null and not v_is_own then
    if public.users_have_active_block(v_viewer, v_profile_id) then
      return jsonb_build_object(
        'meta', jsonb_build_object(
          'contract_version', 1,
          'found', true,
          'can_view', false,
          'is_own', false
        ),
        'data', jsonb_build_object('accounts', '[]'::jsonb)
      );
    end if;

    select exists (
      select 1 from public.followers f
      where f.follower_id = v_viewer and f.following_id = v_profile_id
    ) into v_is_following;
  end if;

  v_can_view := v_is_own
    or coalesce(v_profile.is_private, false) = false
    or v_is_following;

  if not v_can_view then
    return jsonb_build_object(
      'meta', jsonb_build_object(
        'contract_version', 1,
        'found', true,
        'can_view', false,
        'is_own', v_is_own
      ),
      'data', jsonb_build_object('accounts', '[]'::jsonb)
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'category', a.category,
        'type', a.mode,
        'custom_status', a.custom_public_status,
        'payout_total', coalesce(p.total, 0),
        'payouts', coalesce(p.entries, '[]'::jsonb)
      )
      order by a.created_at asc nulls last, a.id asc
    ),
    '[]'::jsonb
  )
  into v_accounts
  from public.accounts a
  left join lateral (
    select
      coalesce(sum(e.amount), 0) as total,
      coalesce(
        jsonb_agg(
          jsonb_build_object(
            'id', e.id,
            'amount', e.amount,
            'payout_date', to_char(e.payout_date, 'YYYY-MM-DD'),
            'note', e.note
          )
          order by e.payout_date desc, e.id desc
        ) filter (where e.id is not null),
        '[]'::jsonb
      ) as entries
    from public.account_payout_entries e
    where e.account_id = a.id
  ) p on true
  where a.user_id = v_profile_id;

  return jsonb_build_object(
    'meta', jsonb_build_object(
      'contract_version', 1,
      'found', true,
      'can_view', true,
      'is_own', v_is_own
    ),
    'data', jsonb_build_object('accounts', v_accounts)
  );
end;
$$;

comment on function public.rpc_v1_profile_account_insights(text) is
  'Public profile account cards (whitelisted fields). SECURITY DEFINER read gateway; '
  'honors profile privacy, follower access, and user blocks. Does not expose raw account rows.';

revoke all on function public.rpc_v1_profile_account_insights(text) from public;
grant execute on function public.rpc_v1_profile_account_insights(text) to authenticated;
grant execute on function public.rpc_v1_profile_account_insights(text) to anon;

-- ---------------------------------------------------------------------------
-- Apply-time catalog assertions only (deterministic; no test data)
-- Behavioral authorization checks: supabase/verification/account_public_insights_authorization.sql
-- ---------------------------------------------------------------------------

do $$
declare
  v_is_definer boolean;
  v_has_block_check boolean;
  v_has_search_path boolean;
  v_anon_mutate boolean;
  v_auth_crud_count integer;
  v_rls_enabled boolean;
  v_policy_count integer;
  v_execute_roles text[];
begin
  select
    p.prosecdef,
    pg_get_functiondef(p.oid) ~ 'users_have_active_block',
    pg_get_functiondef(p.oid) ~ 'search_path'
  into v_is_definer, v_has_block_check, v_has_search_path
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_profile_account_insights'
    and pg_get_function_identity_arguments(p.oid) = 'p_identifier text';

  if coalesce(v_is_definer, false) is not true then
    raise exception 'account_insights_static: rpc_v1_profile_account_insights must be SECURITY DEFINER';
  end if;

  if coalesce(v_has_block_check, false) is not true then
    raise exception 'account_insights_static: rpc must reference users_have_active_block';
  end if;

  if coalesce(v_has_search_path, false) is not true then
    raise exception 'account_insights_static: rpc must set search_path';
  end if;

  if to_regclass('public.account_payout_entries') is null then
    raise exception 'account_insights_static: public.account_payout_entries must exist';
  end if;

  select c.relrowsecurity
  into v_rls_enabled
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname = 'account_payout_entries';

  if coalesce(v_rls_enabled, false) is not true then
    raise exception 'account_insights_static: RLS must be enabled on account_payout_entries';
  end if;

  select count(*)::integer
  into v_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'account_payout_entries'
    and policyname in (
      'account_payout_entries_select_own',
      'account_payout_entries_insert_own',
      'account_payout_entries_update_own',
      'account_payout_entries_delete_own'
    );

  if v_policy_count <> 4 then
    raise exception 'account_insights_static: expected four owner payout RLS policies';
  end if;

  select exists (
    select 1
    from information_schema.role_table_grants g
    where g.table_schema = 'public'
      and g.table_name = 'account_payout_entries'
      and g.grantee = 'anon'
      and g.privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ) into v_anon_mutate;

  if v_anon_mutate then
    raise exception 'account_insights_static: anon must not have payout-table mutation grants';
  end if;

  select count(distinct g.privilege_type)::integer
  into v_auth_crud_count
  from information_schema.role_table_grants g
  where g.table_schema = 'public'
    and g.table_name = 'account_payout_entries'
    and g.grantee = 'authenticated'
    and g.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');

  if v_auth_crud_count <> 4 then
    raise exception 'account_insights_static: authenticated requires payout-table CRUD grants';
  end if;

  select array_agg(distinct grantee::text order by grantee::text)
  into v_execute_roles
  from information_schema.routine_privileges rp
  where rp.specific_schema = 'public'
    and rp.routine_name = 'rpc_v1_profile_account_insights'
    and rp.privilege_type = 'EXECUTE'
    and rp.grantee in ('anon', 'authenticated', 'PUBLIC');

  if v_execute_roles is distinct from array['anon', 'authenticated']::text[] then
    raise exception 'account_insights_static: rpc EXECUTE must be granted only to anon and authenticated';
  end if;

  raise notice 'account_insights_static: passed';
end;
$$;
