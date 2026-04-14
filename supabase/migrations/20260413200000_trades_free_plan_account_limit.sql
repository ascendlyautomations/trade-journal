-- Free (non-Pro) users: at most one distinct (account_type, account_size, account_id)
-- on non-backtest trades. Backtests are excluded.

create or replace function public.trades_enforce_free_plan_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_pro_user boolean;
  new_key text;
  other_count int;
  key_matches boolean;
begin
  if coalesce(new.mode, '') = 'backtest' then
    return new;
  end if;

  is_pro_user := false;
  select coalesce(p.is_pro, false)
    or lower(trim(coalesce(p.subscription_status::text, ''))) = 'active'
  into is_pro_user
  from public.profiles p
  where p.id = new.user_id;

  if not found then
    is_pro_user := false;
  end if;

  if coalesce(is_pro_user, false) then
    return new;
  end if;

  new_key := concat_ws(
    '|',
    lower(trim(coalesce(new.account_type::text, ''))),
    trim(coalesce(new.account_size::text, '')),
    trim(coalesce(new.account_id::text, ''))
  );

  select count(
    distinct concat_ws(
      '|',
      lower(trim(coalesce(t.account_type::text, ''))),
      trim(coalesce(t.account_size::text, '')),
      trim(coalesce(t.account_id::text, ''))
    )
  )
  into other_count
  from public.trades t
  where t.user_id = new.user_id
    and coalesce(t.mode, '') <> 'backtest'
    and (tg_op = 'INSERT' or t.id <> new.id);

  select exists (
    select 1
    from public.trades t
    where t.user_id = new.user_id
      and coalesce(t.mode, '') <> 'backtest'
      and (tg_op = 'INSERT' or t.id <> new.id)
      and concat_ws(
        '|',
        lower(trim(coalesce(t.account_type::text, ''))),
        trim(coalesce(t.account_size::text, '')),
        trim(coalesce(t.account_id::text, ''))
      ) = new_key
  )
  into key_matches;

  if coalesce(other_count, 0) >= 1 and not coalesce(key_matches, false) then
    raise exception 'FREE_PLAN_ACCOUNT_LIMIT'
      using hint = 'Free plan allows only one trading account. Upgrade to Pro for unlimited accounts.';
  end if;

  return new;
end;
$$;

drop trigger if exists trades_enforce_free_plan_accounts on public.trades;

create trigger trades_enforce_free_plan_accounts
before insert or update on public.trades
for each row
execute procedure public.trades_enforce_free_plan_accounts();
