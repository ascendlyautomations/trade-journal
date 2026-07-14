-- Idempotent creator redeem: same user + same code returns 'already' (success),
-- never 'invalid' / 'exhausted'. Exhausted only for a different user when slots
-- are full. Also returns exhausted/no_profile instead of conflating with invalid.

create or replace function public.redeem_creator_access_code(
  p_code text,
  p_user_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized text := upper(trim(coalesce(p_code, '')));
  invite public.creator_access_codes%rowtype;
  used_count int;
  granted_at timestamptz := now();
begin
  if p_user_id is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  if normalized = '' then
    return 'invalid';
  end if;

  select * into invite
  from public.creator_access_codes c
  where c.code = normalized
  for update;

  if not found
     or invite.is_active is not true
     or (invite.expires_at is not null and invite.expires_at <= now()) then
    return 'invalid';
  end if;

  -- Same user already redeemed THIS code (or already has creator access):
  -- idempotent success BEFORE max_redemptions accounting.
  if exists (
    select 1 from public.creator_code_redemptions r
    where r.code = normalized and r.user_id = p_user_id
  ) or exists (
    select 1 from public.profiles p
    where p.id = p_user_id
      and (
        coalesce(p.creator_access, false) = true
        or upper(trim(coalesce(p.creator_code, ''))) = normalized
      )
  ) then
    update public.profiles
    set
      creator_access = true,
      creator_code = coalesce(
        nullif(upper(trim(coalesce(creator_code, ''))), ''),
        normalized
      ),
      creator_granted_at = coalesce(creator_granted_at, granted_at),
      is_pro = true
    where id = p_user_id;
    return 'already';
  end if;

  select count(*)::int into used_count
  from public.creator_code_redemptions r
  where r.code = normalized;

  if coalesce(used_count, 0) >= invite.max_redemptions then
    return 'exhausted';
  end if;

  update public.profiles
  set
    creator_access = true,
    creator_code = normalized,
    creator_granted_at = granted_at,
    is_pro = true
  where id = p_user_id;

  if not found then
    return 'no_profile';
  end if;

  insert into public.creator_code_redemptions (code, user_id, redeemed_at)
  values (normalized, p_user_id, granted_at)
  on conflict (code, user_id) do nothing;

  update public.accounts
  set can_add_trades = true
  where user_id = p_user_id;

  return 'ok';
end;
$$;

revoke all on function public.redeem_creator_access_code(text, uuid) from public;
grant execute on function public.redeem_creator_access_code(text, uuid) to service_role;

comment on function public.redeem_creator_access_code(text, uuid) is
  'Service-role redeem of a creator invite code. Returns ok | already | exhausted | no_profile | invalid. Same-user re-redeem is idempotent (already).';
