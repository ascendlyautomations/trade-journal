-- Allow username availability checks before signup (anonymous clients cannot read profiles via RLS).

create or replace function public.profile_username_is_taken(check_username text)
returns boolean
language sql
security definer
set search_path = public
stable
parallel safe
as $$
  select exists (
    select 1
    from public.profiles p
    where p.username = trim(lower(coalesce(check_username, '')))
    limit 1
  );
$$;

grant execute on function public.profile_username_is_taken(text) to anon;
grant execute on function public.profile_username_is_taken(text) to authenticated;
