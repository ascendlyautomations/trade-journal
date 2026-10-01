-- Owners can delete avatar objects in their own folder.
-- Insert/update already require the first folder to be auth.uid().
-- Replacing a profile photo or a room image stored under that folder
-- could not remove the previous object. Account deletion uses the service
-- role and is unchanged. Legacy room-images/ objects stay until a service
-- cleanup; new room uploads use {user id}/room-images/ so this policy applies.

drop policy if exists "avatars_storage_delete_own" on storage.objects;
create policy "avatars_storage_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
