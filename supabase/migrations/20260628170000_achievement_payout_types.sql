-- Split legacy generic `payout` achievements into prop firm vs live trading types.
--
-- Confident prop firm signals (any one):
--   • metadata.source = 'prop_firm_mode'
--   • firm is set AND account_size is set (prop firm milestone pre-fill)
--
-- Remaining legacy `payout` rows default to live_trading_payout (manual achievement default).
-- Ambiguous rows without firm/account context are NOT guessed as prop firm.

update public.achievements
set
  achievement_type = 'prop_firm_payout',
  category = 'prop_firm_payouts',
  badge_key = 'prop_firm_payout'
where achievement_type = 'payout'
  and (
    coalesce(metadata->>'source', '') = 'prop_firm_mode'
    or (
      nullif(trim(coalesce(firm, '')), '') is not null
      and nullif(trim(coalesce(account_size, '')), '') is not null
    )
  );

update public.achievements
set
  achievement_type = 'live_trading_payout',
  category = 'live_trading_payouts',
  badge_key = 'live_trading_payout'
where achievement_type = 'payout';
