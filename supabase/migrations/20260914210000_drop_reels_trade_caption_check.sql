-- Reel caption and linked trade are independent (Create Reel + link-existing flows).

alter table public.reels
  drop constraint if exists reels_trade_caption_check;

comment on column public.reels.trade_id is
  'Optional link to a trade. Reel caption remains independent when both are set.';
