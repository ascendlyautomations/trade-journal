-- Beta launch security: RLS gaps, profile privilege protection, storage insert scoping.

-- ---------------------------------------------------------------------------
-- referrals: financial ledger — users may only read their own rows
-- ---------------------------------------------------------------------------
alter table public.referrals enable row level security;

revoke all on public.referrals from anon;

drop policy if exists "referrals_select_own" on public.referrals;
create policy "referrals_select_own"
  on public.referrals
  for select
  to authenticated
  using (
    referrer_user_id = auth.uid()
    or referred_user_id = auth.uid()
  );

-- Writes only via service role (Stripe webhook).

-- ---------------------------------------------------------------------------
-- room_sections: scoped to room members (read) and owners (write)
-- ---------------------------------------------------------------------------
alter table public.room_sections enable row level security;

revoke all on public.room_sections from anon;

drop policy if exists "room_sections_select_member" on public.room_sections;
create policy "room_sections_select_member"
  on public.room_sections
  for select
  to authenticated
  using (
    public.is_active_room_member(room_id, auth.uid())
    or public.is_room_owner(room_id, auth.uid())
  );

drop policy if exists "room_sections_insert_owner" on public.room_sections;
create policy "room_sections_insert_owner"
  on public.room_sections
  for insert
  to authenticated
  with check (public.is_room_owner(room_id, auth.uid()));

drop policy if exists "room_sections_update_owner" on public.room_sections;
create policy "room_sections_update_owner"
  on public.room_sections
  for update
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()))
  with check (public.is_room_owner(room_id, auth.uid()));

drop policy if exists "room_sections_delete_owner" on public.room_sections;
create policy "room_sections_delete_owner"
  on public.room_sections
  for delete
  to authenticated
  using (public.is_room_owner(room_id, auth.uid()));

-- ---------------------------------------------------------------------------
-- profiles: block self-service subscription / import bypass fields
-- ---------------------------------------------------------------------------
create or replace function public.profiles_reject_privileged_self_update()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if public.rate_limit_is_service_role() then
    return new;
  end if;

  if exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  ) then
    return new;
  end if;

  if auth.uid() is null or auth.uid() <> old.id then
    return new;
  end if;

  -- referred_by is set at signup insert only; never self-updatable.
  if new.referred_by is distinct from old.referred_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_pro is distinct from old.is_pro then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_beta_tester is distinct from old.is_beta_tester then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.use_free_tier is distinct from old.use_free_tier then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.trial_end is distinct from old.trial_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.has_used_csv_import is distinct from old.has_used_csv_import then
    if coalesce(old.has_used_csv_import, false) = true then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
    if coalesce(new.has_used_csv_import, false) = false then
      raise exception 'Protected profile fields cannot be modified.';
    end if;
  end if;

  if new.subscription_status is distinct from old.subscription_status then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_customer_id is distinct from old.stripe_customer_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.stripe_price_id is distinct from old.stripe_price_id then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.billing_interval is distinct from old.billing_interval then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at_period_end is distinct from old.cancel_at_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.cancel_at is distinct from old.cancel_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.current_period_end is distinct from old.current_period_end then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_earnings is distinct from old.referral_earnings then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.referral_count is distinct from old.referral_count then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.is_banned is distinct from old.is_banned then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_by is distinct from old.banned_by then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_at is distinct from old.banned_at then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  if new.banned_reason is distinct from old.banned_reason then
    raise exception 'Protected profile fields cannot be modified.';
  end if;

  return new;
end;
$$;

comment on function public.profiles_reject_privileged_self_update() is
  'Blocks authenticated users from self-updating billing, referral, ban, and import flags. Service role and admins exempt.';

-- ---------------------------------------------------------------------------
-- Storage: scope INSERT to caller folder on public buckets
-- ---------------------------------------------------------------------------
drop policy if exists "reels_storage_insert" on storage.objects;
create policy "reels_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'reels'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "stories_storage_insert" on storage.objects;
create policy "stories_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'stories'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "profile_posts_storage_insert" on storage.objects;
create policy "profile_posts_storage_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'profile_posts'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
