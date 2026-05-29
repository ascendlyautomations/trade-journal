-- Private storage for user-submitted CSV samples (broker/platform support requests).

insert into storage.buckets (id, name, public)
values ('csv-support', 'csv-support', false)
on conflict (id) do update set public = excluded.public;

create policy "csv_support_storage_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'csv-support'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

create policy "csv_support_storage_select_own"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'csv-support'
    and auth.uid()::text = (storage.foldername (name))[1]
  );

create policy "csv_support_storage_select_admin"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'csv-support'
    and exists (
      select 1
      from public.admin_users au
      where au.user_id = auth.uid()
    )
  );

create policy "csv_support_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'csv-support'
    and auth.uid()::text = (storage.foldername (name))[1]
  );
