-- User reviews (beta today; all users later). Replaces beta_testimonials.

create table if not exists public.user_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  rating smallint not null,
  title text,
  review text not null,
  would_recommend boolean not null default true,
  status text not null default 'pending',
  featured boolean not null default false,
  display_name text,
  username_snapshot text,
  avatar_snapshot text,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_reviews_user_id_unique unique (user_id),
  constraint user_reviews_rating_ck check (rating between 1 and 5),
  constraint user_reviews_review_ck check (char_length(trim(review)) > 0),
  constraint user_reviews_status_ck check (status in ('pending', 'approved', 'rejected')),
  constraint user_reviews_featured_requires_approved_ck check (
    featured = false or status = 'approved'
  )
);

create index if not exists user_reviews_status_featured_created_idx
  on public.user_reviews (status, featured desc, created_at desc);

create index if not exists user_reviews_user_id_idx
  on public.user_reviews (user_id);

create or replace function public.user_reviews_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_reviews_set_updated_at_trigger on public.user_reviews;
create trigger user_reviews_set_updated_at_trigger
  before update on public.user_reviews
  for each row
  execute function public.user_reviews_set_updated_at();

create or replace function public.user_reviews_guard_user_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_admin boolean;
  content_changed boolean;
begin
  select exists (
    select 1 from public.admin_users au where au.user_id = auth.uid()
  ) into is_admin;

  if is_admin then
    return new;
  end if;

  if auth.uid() is distinct from old.user_id then
    raise exception 'not authorized';
  end if;

  new.featured := old.featured;
  new.status := old.status;

  content_changed := (
    trim(coalesce(new.title, '')) is distinct from trim(coalesce(old.title, ''))
    or trim(coalesce(new.review, '')) is distinct from trim(coalesce(old.review, ''))
    or new.rating is distinct from old.rating
    or new.would_recommend is distinct from old.would_recommend
    or trim(coalesce(new.display_name, '')) is distinct from trim(coalesce(old.display_name, ''))
    or trim(coalesce(new.username_snapshot, '')) is distinct from trim(coalesce(old.username_snapshot, ''))
    or trim(coalesce(new.avatar_snapshot, '')) is distinct from trim(coalesce(old.avatar_snapshot, ''))
  );

  if content_changed then
    new.status := 'pending';
    new.featured := false;
    new.version := old.version + 1;
  end if;

  return new;
end;
$$;

drop trigger if exists user_reviews_guard_user_update_trigger on public.user_reviews;
create trigger user_reviews_guard_user_update_trigger
  before update on public.user_reviews
  for each row
  execute function public.user_reviews_guard_user_update();

-- Migrate legacy beta_testimonials rows when present.
do $$
begin
  if to_regclass('public.beta_testimonials') is not null then
    insert into public.user_reviews (
  id,
  user_id,
  rating,
  title,
  review,
  would_recommend,
  status,
  featured,
  display_name,
  username_snapshot,
  avatar_snapshot,
  version,
  created_at,
  updated_at
)
select
  t.id,
  t.user_id,
  t.rating,
  nullif(trim(t.title), ''),
  t.review,
  t.would_recommend,
  case when t.approved then 'approved' else 'pending' end,
  t.featured,
  nullif(trim(p.name), ''),
  nullif(trim(p.username), ''),
  nullif(trim(p.avatar_url), ''),
  1,
  t.created_at,
  t.updated_at
from public.beta_testimonials t
left join public.profiles p on p.id = t.user_id
on conflict (user_id) do nothing;
  end if;
end $$;

alter table public.user_reviews enable row level security;

drop policy if exists "user_reviews_select_own" on public.user_reviews;
drop policy if exists "user_reviews_select_public_approved" on public.user_reviews;
drop policy if exists "user_reviews_insert_beta" on public.user_reviews;
drop policy if exists "user_reviews_update_own" on public.user_reviews;
drop policy if exists "user_reviews_admin_select" on public.user_reviews;
drop policy if exists "user_reviews_admin_update" on public.user_reviews;
drop policy if exists "user_reviews_admin_delete" on public.user_reviews;

create policy "user_reviews_select_own"
  on public.user_reviews
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "user_reviews_select_public_approved"
  on public.user_reviews
  for select
  to anon, authenticated
  using (status = 'approved');

create policy "user_reviews_insert_beta"
  on public.user_reviews
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and coalesce(p.is_beta_tester, false) = true
    )
    and rating between 1 and 5
    and char_length(trim(review)) > 0
    and status = 'pending'
    and featured = false
  );

create policy "user_reviews_update_own"
  on public.user_reviews
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "user_reviews_admin_select"
  on public.user_reviews
  for select
  to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

create policy "user_reviews_admin_update"
  on public.user_reviews
  for update
  to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

create policy "user_reviews_admin_delete"
  on public.user_reviews
  for delete
  to authenticated
  using (
    exists (select 1 from public.admin_users au where au.user_id = auth.uid())
  );

grant select, insert, update on table public.user_reviews to authenticated;
grant select on table public.user_reviews to anon;

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
    r.avatar_snapshot
  from public.user_reviews r
  where r.status = 'approved'
  order by r.featured desc, r.created_at desc;
$$;

grant execute on function public.list_public_user_reviews() to anon, authenticated;

comment on table public.user_reviews is
  'User-submitted reviews; approved+featured rows surface on the marketing homepage.';

-- Retire legacy table after migration.
drop function if exists public.list_public_beta_testimonials();
drop table if exists public.beta_testimonials cascade;
