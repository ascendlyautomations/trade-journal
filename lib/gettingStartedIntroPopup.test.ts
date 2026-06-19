import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"
import pg from "pg"

const env = Object.fromEntries(
  readFileSync(".env.local", "utf8")
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=")
      return [l.slice(0, i), l.slice(i + 1)]
    })
)

const ref = env.NEXT_PUBLIC_SUPABASE_URL.match(/https:\/\/([^.]+)/)?.[1]
const connStr =
  env.DATABASE_URL ||
  (env.SUPABASE_DB_PASSWORD
    ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
    : null)

if (!connStr) {
  console.error("Missing DATABASE_URL or SUPABASE_DB_PASSWORD")
  process.exit(1)
}

const client = new pg.Client({
  connectionString: connStr,
  ssl: { rejectUnauthorized: false },
})
await client.connect()

const cols = await client.query(`
  SELECT column_name, is_nullable, column_default, data_type
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'profiles'
  ORDER BY ordinal_position
`)
console.log("=== profiles columns (key fields) ===")
for (const r of cols.rows) {
  if (
    [
      "username",
      "name",
      "referral_code",
      "referred_by",
      "subscription_status",
      "is_pro",
      "created_at",
      "id",
    ].includes(r.column_name)
  ) {
    console.log(
      r.column_name,
      "nullable=" +If you want to use the same pattern as the other tests, you can use `require` instead of `import` in the test file. Let me check how other tests in the project import modules.


Read