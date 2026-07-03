-- Beta tester testimonials for homepage social proof.

create table if not exists public.beta_testimonials (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  rating smallint not null,
  title text not null,
  review text not null,
  pros text,
  cons text,
  would_recommend boolean not null default true,
  approved boolean not null default false,
  featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint beta_testimonials_user_id_unique unique (user_id),
  constraint beta_testimonials_rating_ck check (rating between 1 and 5),
  constraint beta_testimonials_title_ck check (char_length(trim(title)) > 0),
  constraint beta_testimonials_review_ck check (char_length(trim(review)) > 0)
);

create index if not exists beta_testimonials_approved_featured_created_idx
  on public.beta_testimonials (approved, featured desc, created_at desc);

create index if not exists beta_testimonials_user_id_idx
  on public.beta_testimonials (user_id);

create or replace function public.beta_testimonials_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists beta_testimonials_set_updated_at_trigger on public.beta_testimonials;
create trigger beta_testimonials_set_updated_at_trigger
  before update on public.beta_testimonials
  for each row
  execute function public.beta_testimonials_set_updated_at();

create or replace function public.beta_testimonials_guard_user_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_admin boolean;
begin
  select exists (
    select 1
    from public.admin_users au
    where au.user_id = auth.uid()
  ) into is_admin;

  if is_admin then
    return new;
  end if;

  if auth.uid() is distinct from old.user_id then
    raise exception 'not authorized';
  end if;

  new.featured := old.featured;

  if (
    trim(coalesce(new.title, '')) is distinct from trim(coalesce(old.title, ''))
    or trim(coalesce(new.review, '')) is distinct from trim(coalesce(old.review, ''))
    or trim(coalesce(new.pros, '')) is distinct from trim(coalesce(old.pros, ''))
    or trim(coalesce(new.cons, '')) is distinct from trim(coalesce(old.cons, ''))
    or new.rating is distinct from old.rating
  ) then
    new.approved := false;
  else
    new.approved := old.approved;
  end if;

  return new;
end;
$$;

drop trigger if exists beta_testimonials_guard_user_update_trigger on public.beta_testimonials;
create trigger beta_testimonials_guard_user_update_trigger
  before update on public.beta_testimonials
  for each row
  execute function public.beta_testimonials_guard_user_update();

alter table public.beta_testimonials enable row level security;

drop policy if exists "beta_testimonials_select_own" on public.beta_testimonials;
drop policy if exists "beta_testimonials_select_public_approved" on public.beta_testimonials;
drop policy if exists "beta_testimonials_insert_beta" on public.beta_testimonials;
drop policy if exists "beta_testimonials_update_own" on public.beta_testimonials;
drop policy if exists "beta_testimonials_admin_select" on public.beta_testimonials;
drop policy if exists "beta_testimonials_admin_update" on public.beta_testimonials;
drop policy if exists "beta_testimonials_admin_delete" on public.beta_testimonials;

create policy "beta_testimonials_select_own"
  on public.beta_testimonials
  for select
  to authenticated
  using (user_id = auth.uid());

create policy "beta_testimonials_select_public_approved"
  on public.beta_testimonials
  for select
  to anon, authenticated
  using (approved = true);

create policy "beta_testimonials_insert_beta"
  on public.beta_testimonials
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
    and char_length(trim(title)) > 0
    and char_length(trim(review)) > 0
    and approved = false
    and featured = false
  );

create policy "beta_testimonials_update_own"
  on public.beta_testimonials
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "beta_testimonials_admin_select"
  on public.beta_testimonials
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "beta_testimonials_admin_update"
  on public.beta_testimonials
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "beta_testimonials_admin_delete"
  on public.beta_testimonials
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

grant select, insert, update on table public.beta_testimonials to authenticated;
grant select on table public.beta_testimonials to anon;

create or replace function public.list_public_beta_testimonials()
returns table (
  id uuid,
  rating smallint,
  title text,
  review text,
  pros text,
  cons text,
  would_recommend boolean,
  featured boolean,
  created_at timestamptz,
  username text,
  avatar_url text,
  trading_style text,
  trader_type text,
  started_trading text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.id,
    t.rating,
    t.title,
    t.review,
    t.pros,
    t.cons,
    t.would_recommend,
    t.featured,
    t.created_at,
    p.username,
    p.avatar_url,
    p.trading_style,
    p.trader_type,
    p.started_trading
  from public.beta_testimonials t
  inner join public.profiles p on p.id = t.user_id
  where t.approved = true
  order by t.featured desc, t.created_at desc;
$$;

grant execute on function public.list_public_beta_testimonials() to anon, authenticated;

comment on table public.beta_testimonials is
  'Beta tester testimonials; approved rows surface on the marketing homepage.';
