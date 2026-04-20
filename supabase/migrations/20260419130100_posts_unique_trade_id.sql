-- One community post per trade — enables upsert by trade_id from edit flow.
create unique index if not exists posts_trade_id_uidx on public.posts (trade_id);
