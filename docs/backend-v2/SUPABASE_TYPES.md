# Supabase TypeScript types (`lib/database.types.ts`)

## Regeneration

```bash
export SUPABASE_PROJECT_ID=fobudrkniacatvilbofw
npm run types:supabase
```

Alternate (Supabase MCP, read-only):

```
generate_typescript_types({ project_id: "fobudrkniacatvilbofw" })
```

Requires `SUPABASE_ACCESS_TOKEN` or `supabase login` for CLI. The project ref is not a secret.

## Source

- **Project:** TradeTraxs (`fobudrkniacatvilbofw`, us-east-2)
- **Schema:** `public` only
- **File:** `lib/database.types.ts` — auto-generated; do not hand-edit table/function definitions

## Helpers

Use `lib/supabaseTypes.ts` for `TableRow`, `TableInsert`, `TableUpdate`, and `AppSupabaseClient`.

## `suggestions` table mismatch (2026-08-24)

Live schema inspection shows **`public.suggestions` does not exist**. User feedback is stored in **`public.feedback_submissions`**.

| Finding | Detail |
|--------|--------|
| Table | `public.suggestions` — **absent** |
| Replacement | `public.feedback_submissions` (RLS enabled, exposed via PostgREST) |
| Columns (feedback) | `id`, `user_id`, `email`, `subject`, `message`, `screenshot_url`, `status`, `admin_notes`, `created_at`, `updated_at`, `viewed`, `viewed_at`, `viewed_by` |
| PK | `id` (uuid, default `gen_random_uuid()`) |
| FK | `user_id` → `profiles`, `viewed_by` → `profiles` |
| Privileges | `anon` and `authenticated` have INSERT/SELECT/UPDATE/DELETE on `feedback_submissions` |

`app/suggestions/page.tsx` was updated to insert into `feedback_submissions` (columns `message`, `screenshot_url`, `status`) instead of the non-existent `suggestions` table. Storage uploads still use the `suggestions` bucket name where configured.

Do **not** manually add fabricated table definitions to `database.types.ts`.
