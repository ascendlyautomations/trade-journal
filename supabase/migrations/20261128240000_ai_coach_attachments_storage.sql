-- Private AI coach image attachments (Trade AI + Psychology follow-ups).
-- Apply after 20261128233000_ai_coach_server_persist.sql.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ai-coach-attachments',
  'ai-coach-attachments',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists ai_coach_attachments_select_own on storage.objects;
create policy ai_coach_attachments_select_own
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'ai-coach-attachments'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists ai_coach_attachments_insert_own on storage.objects;
create policy ai_coach_attachments_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'ai-coach-attachments'
    and auth.uid()::text = (storage.foldername(name))[1]
    and not public.guest_session_is_read_only()
  );