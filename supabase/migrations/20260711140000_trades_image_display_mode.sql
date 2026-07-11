-- Persist Fit vs Fill for trade screenshot previews (CSS object-fit).
-- Existing rows default to 'fit' so the entire uploaded image remains visible.

alter table public.trades
  add column if not exists image_display_mode text;

update public.trades
set image_display_mode = 'fit'
where image_display_mode is null;

alter table public.trades
  alter column image_display_mode set default 'fit';

alter table public.trades
  alter column image_display_mode set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'trades_image_display_mode_check'
  ) then
    alter table public.trades
      add constraint trades_image_display_mode_check
      check (image_display_mode in ('fit', 'fill'));
  end if;
end $$;
