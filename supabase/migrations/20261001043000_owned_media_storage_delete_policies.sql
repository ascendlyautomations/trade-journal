-- Owners can delete their own screenshot and voice-message objects.
-- Insert/update policies already require the first folder to be auth.uid().
-- Delete policies were missing, so trade screenshots and voice files stayed
-- after the database row was removed. Account deletion uses the service role
-- and is unchanged.

drop policy if exists "screenshots_storage_delete_own" on storage.objects;
create policy "screenshots_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'screenshots'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "message_audio_storage_delete_own" on storage.objects;
create policy "message_audio_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'message-audio'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
