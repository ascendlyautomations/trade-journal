-- Homepage reviews: prefer stored avatar snapshot, fall back to live profile photo.

create or replace function public.list_public_user_reviews()
returns table (
  id uuid,
  rating smallint,
  title text,
  review text,
  would_recommend boolean,
  featured boolean,
  created_at timestamptz,
  display_name text,
  username_snapshot text,
  avatar_snapshot text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.rating,
    r.title,
    r.review,
    r.would_recommend,
    r.featured,
    r.created_at,
    r.display_name,
    r.username_snapshot,
    coalesce(
      nullif(trim(r.avatar_snapshot), ''),
      nullif(trim(p.avatar_url), '')
    ) as avatar_snapshot
  from public.user_reviews r
  left join public.profiles p on p.id = r.user_id
  where r.status = 'approved'
  order by r.featured desc, r.created_at desc;
$$;

grant execute on function public.list_public_user_reviews() to anon, authenticated;
