-- Remap legacy inverted calmness scale (1 = most stressed, 5 = calm) to stress scale (1 = calm, 5 = very stressed).
update public.trader_daily_check_ins
set stress_level = (6 - stress_level)::smallint,
    updated_at = now()
where stress_level is not null;

comment on column public.trader_daily_check_ins.stress_level is
  'Self-reported stress from 1 (calm) through 5 (very stressed).';
