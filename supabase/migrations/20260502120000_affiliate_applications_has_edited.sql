-- Single edit lock while application is pending (stored on affiliate_applications, not affiliates).

alter table public.affiliate_applications
  add column if not exists has_edited boolean not null default false;

comment on column public.affiliate_applications.has_edited is
  'True after the applicant used their one allowed edit while status is pending.';
