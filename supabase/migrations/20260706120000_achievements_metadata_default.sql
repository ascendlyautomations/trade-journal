-- achievements.metadata is NOT NULL; app must send jsonb on insert.
-- Backfill any legacy nulls and add a default so omitted columns still succeed.

update public.achievements
set metadata = '{}'::jsonb
where metadata is null;

alter table public.achievements
  alter column metadata set default '{}'::jsonb;

comment on column public.achievements.metadata is
  'Extensible achievement snapshot (e.g. source=prop_firm_mode). NOT NULL; use {} when empty.';
