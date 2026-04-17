-- Minimal affiliate_applications shape + admin row updates (no legacy columns).

alter table public.affiliate_applications add column if not exists followers integer;

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'affiliate_applications' and column_name = 'audience_size'
  ) then
    execute $e$
      update public.affiliate_applications
      set followers = coalesce(
        followers,
        nullif(regexp_replace(trim(audience_size::text), '[^0-9]', '', 'g'), '')::integer
      )
      where followers is null
    $e$;
  end if;
end $$;

alter table public.affiliate_applications drop column if exists email;
alter table public.affiliate_applications drop column if exists full_name;
alter table public.affiliate_applications drop column if exists platform;
alter table public.affiliate_applications drop column if exists audience_size;
alter table public.affiliate_applications drop column if exists why_join;
alter table public.affiliate_applications drop column if exists promo_plan;
alter table public.affiliate_applications drop column if exists approved_code;
alter table public.affiliate_applications drop column if exists admin_notes;
alter table public.affiliate_applications drop column if exists updated_at;
alter table public.affiliate_applications drop column if exists experience;
alter table public.affiliate_applications drop column if exists why;

drop policy if exists "affiliate_applications_update_admin" on public.affiliate_applications;

create policy "affiliate_applications_update_admin"
  on public.affiliate_applications for update to authenticated
  using (exists (select 1 from public.admin_users au where au.user_id = auth.uid()))
  with check (exists (select 1 from public.admin_users au where au.user_id = auth.uid()));

-- Old RPCs referenced removed columns; drop if present.
drop function if exists public.admin_affiliate_application_approve(uuid, text, text, text);
drop function if exists public.admin_affiliate_application_reject(uuid, text);
