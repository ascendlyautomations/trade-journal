-- Story private bucket production audit (run in Supabase SQL editor, read-only).
-- Pair with HTTP check: POST .../storage/v1/object/sign/stories/{path} then
-- GET  https://{project}.supabase.co/storage/v1{signedURL}  → expect 200 + image/jpeg.

-- Bucket
select id, public from storage.buckets where id = 'stories';

-- Active story objects (path match)
select s.id,
       s.user_id,
       public.story_row_storage_path(s) as object_path,
       o.id is not null as object_exists,
       o.metadata->>'mimetype' as mime,
       (o.metadata->>'size')::bigint as size_bytes,
       public.story_is_publicly_active(s.created_at) as active_24h
from public.stories s
left join storage.objects o
  on o.bucket_id = 'stories'
 and o.name = public.story_row_storage_path(s)
where s.created_at > now() - interval '48 hours'
order by s.created_at desc
limit 20;

-- Storage SELECT policies (expect stories_storage_select only for stories bucket)
select policyname, roles::text, qual
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and qual ilike '%stories%';

-- Owner readability simulation (set jwt.claim.sub to story owner uuid first)
-- select set_config('request.jwt.claim.sub', '<owner-uuid>', true);
-- select public.story_storage_object_readable('<object-path>');