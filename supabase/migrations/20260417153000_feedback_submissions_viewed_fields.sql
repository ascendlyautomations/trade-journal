alter table public.feedback_submissions
  add column if not exists viewed boolean not null default false;

alter table public.feedback_submissions
  add column if not exists viewed_at timestamptz;

alter table public.feedback_submissions
  add column if not exists viewed_by uuid;

