-- Authenticated upserts evaluate trading_preferences CHECK constraints in the
-- caller's security context. The immutable validators must remain callable by
-- authenticated; revoking EXECUTE (bootstrap migrations) caused:
--   permission denied for function trading_preference_weekdays_ok
-- public and anon stay without EXECUTE.

grant execute on function public.trading_preference_symbols_ok(text[])
  to authenticated;

grant execute on function public.trading_preference_weekdays_ok(text[])
  to authenticated;

grant execute on function public.trading_preference_scope_ok(text)
  to authenticated;
