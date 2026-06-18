-- Public trade room search for onboarding join modal (member counts, excludes beta room).

create or replace function public.search_public_trade_rooms(
  p_query text,
  p_limit int default 20
)
returns table (
  id uuid,
  name text,
  description text,
  slug text,
  member_count bigint,
  image_url text
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
    count(m.user_id) as member_count,
    r.image_url
  from public.rooms r
  left join public.room_members m
    on m.room_id = r.id
    and m.left_at is null
  where r.owner_user_id is not null
    and coalesce(r.show_on_profile, true) = true
    and lower(trim(coalesce(r.slug, ''))) <> 'tradetraxs-beta'
    and trim(coalesce(p_query, '')) <> ''
    and (
      r.name ilike '%' || trim(p_query) || '%'
      or r.slug ilike '%' || trim(p_query) || '%'
    )
  group by r.id, r.name, r.description, r.slug, r.image_url
  order by member_count desc, r.name asc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

comment on function public.search_public_trade_rooms(text, int) is
  'Public discovery: profile-visible rooms matching name or slug; excludes tradetraxs-beta.';

grant execute on function public.search_public_trade_rooms(text, int) to authenticated;
grant execute on function public.search_public_trade_rooms(text, int) to anon;
