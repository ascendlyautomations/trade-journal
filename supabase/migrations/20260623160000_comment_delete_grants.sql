-- Idempotent grants for comment delete (if 20260623150000 was applied without grants).

do $$
begin
  if to_regclass('public.comments') is not null then
    grant select, insert, delete on table public.comments to authenticated;
  end if;

  if to_regclass('public.trade_comments') is not null then
    grant select, insert, delete on table public.trade_comments to authenticated;
  end if;
end $$;
