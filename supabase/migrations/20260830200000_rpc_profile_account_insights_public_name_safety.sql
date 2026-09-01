-- Repair: sanitize public profile account card names that embed private account numbers.
-- Does not expose account_number in RPC JSON — uses it only server-side for redaction.

create or replace function public.default_public_account_label(p_mode text, p_category text)
returns text
language sql
immutable
as $$
  select case
    when lower(replace(replace(replace(coalesce(trim(p_category), ''), '_', ''), '-', ''), ' ', ''))
      in ('propfirm', 'prop')
      and lower(coalesce(trim(p_mode), '')) in ('funded')
      then 'Funded Account'
    when lower(replace(replace(replace(coalesce(trim(p_category), ''), '_', ''), '-', ''), ' ', ''))
      in ('propfirm', 'prop')
      then 'Evaluation Account'
    when lower(coalesce(trim(p_mode), '')) in ('backtest')
      or lower(replace(replace(replace(coalesce(trim(p_category), ''), '_', ''), '-', ''), ' ', ''))
      in ('backtest')
      then 'Backtest Account'
    when lower(coalesce(trim(p_mode), '')) in ('sim')
      then 'Sim Account'
    when lower(coalesce(trim(p_mode), '')) in ('live')
      then 'Live Account'
    else 'Trading Account'
  end;
$$;

create or replace function public.safe_public_account_display_name(
  p_name text,
  p_mode text,
  p_category text,
  p_account_number text
)
returns text
language sql
immutable
as $$
  select case
    when coalesce(trim(p_name), '') = '' then
      public.default_public_account_label(p_mode, p_category)
    when coalesce(trim(p_account_number), '') <> ''
      and (
        lower(trim(p_name)) = lower(trim(p_account_number))
        or position(lower(trim(p_account_number)) in lower(trim(p_name))) > 0
      )
      then public.default_public_account_label(p_mode, p_category)
    else trim(p_name)
  end;
$$;

comment on function public.safe_public_account_display_name(text, text, text, text) is
  'Public profile account title — redacts names that equal/contain account_number; never returns the number.';

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
        'name', public.safe_public_account_display_name(
          a.name,
          a.mode,
          a.category,
          a.account_number
        ),
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

do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'safe_public_account_display_name'
  ) then
    raise exception 'account_insights_name_safety: safe_public_account_display_name missing';
  end if;
end;
$$;
