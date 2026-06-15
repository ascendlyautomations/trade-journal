-- Popular trade rooms for onboarding checklist modal (member counts, excludes beta room).

create or replace function public.popular_trade_rooms(p_limit int default 12)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.name,
    r.description,
    r.slug,
    count(m.user_id) as member_count
  from public.rooms r
  left join public.room_members m
    on m.room_id = r.id
    and m.left_at is null
  where r.owner_user_id is not null
    and coalesce(r.show_on_profile, true) = true
    and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
  group by r.id, r.name, r.description, r.slug
  order by member_count desc, r.name asc
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;

comment on function public.popular_trade_rooms(int) is
  'Public discovery: profile-visible rooms by active member count; excludes tradetraxs-beta.';

grant execute on function public.popular_trade_rooms(int) to authenticated;
grant execute on function public.popular_trade_rooms(int) to anon;
