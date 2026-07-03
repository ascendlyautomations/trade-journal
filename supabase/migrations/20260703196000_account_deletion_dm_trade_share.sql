-- Account deletion: keep DM trade-share messages when trades are removed (null trade_id).

do $$
begin
  if to_regclass('public.messages') is not null then
    perform public._replace_fk_to_trades('messages', 'trade_id', 'set null');
  end if;
end;
$$;
