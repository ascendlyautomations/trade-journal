-- TradeTraxs Beta discussion room (system room, no owner).
-- Idempotent: safe to run multiple times.

insert into public.rooms (
  name,
  description,
  slug,
  owner_user_id,
  show_on_profile
)
select
  'TradeTraxs Beta',
  'Beta discussion for bugs, feature requests, product feedback, and ideas.',
  'tradetraxs-beta',
  null,
  false
where not exists (
  select 1
  from public.rooms r
  where lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
);

insert into public.room_sections (room_id, name, position)
select r.id, 'general', 1
from public.rooms r
where lower(trim(coalesce(r.slug, ''))) = 'tradetraxs-beta'
  and not exists (
    select 1
    from public.room_sections s
    where s.room_id = r.id
      and lower(trim(s.name)) = 'general'
  );
