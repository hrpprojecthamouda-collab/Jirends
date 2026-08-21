-- Profile photos.
--
-- Bytes live in the `avatars` Storage bucket at `{user_id}/{unique}.png`;
-- the resulting URL is written to public.profiles.avatar_url (a column that
-- has existed in schema.sql since the beginning and was never used).
--
-- CARDINAL RULE: this adds no visibility path. An avatar is profile data, not
-- event data — public.profiles is already `select using (true)`, so anyone who
-- can see your handle can see your picture, and that is exactly the existing
-- model. The storage path is keyed by USER id and contains no event id, so an
-- avatar cannot encode or hint at membership of anything. Do not extend this
-- bucket to hold anything event-scoped: event bytes belong in
-- `event-attachments`, which is private and gated by is_event_member().
--
-- The bucket is PUBLIC on purpose. Avatars render in long lists (members,
-- friends, comment threads), and signed URLs would mean an extra round trip
-- per face and links that expire mid-scroll. Public read matches what the
-- profiles policy already grants; writes stay locked to the owner below.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880, -- 5 MB, enforced server-side as well as in the client
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Read: anyone. The bucket is public, so this only matters for reads that go
-- through the authenticated API rather than the public CDN URL.
drop policy if exists storage_avatars_select on storage.objects;
create policy storage_avatars_select on storage.objects
  for select using (bucket_id = 'avatars');

-- Write: your own folder only. The first path segment must be your user id,
-- which is what stops one user overwriting another's face.
drop policy if exists storage_avatars_insert on storage.objects;
create policy storage_avatars_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists storage_avatars_update on storage.objects;
create policy storage_avatars_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists storage_avatars_delete on storage.objects;
create policy storage_avatars_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
