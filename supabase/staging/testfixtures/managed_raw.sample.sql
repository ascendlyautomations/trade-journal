-- Sample pg_dump fragment (managed schemas) for filter tests.
CREATE SCHEMA auth;
CREATE SCHEMA storage;

CREATE TABLE auth.users (
    id uuid NOT NULL,
    email text
);

CREATE TABLE storage.buckets (
    id text NOT NULL
);

CREATE TABLE storage.objects (
    id uuid NOT NULL
);

CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  select '{}'::jsonb;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP POLICY IF EXISTS "avatars public read" ON storage.objects;
CREATE POLICY "avatars public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

GRANT SELECT ON TABLE storage.objects TO authenticated;

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;
