import { createClient, type SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types"

const globalForSupabase = globalThis as typeof globalThis & {
  __ttSupabaseBrowser?: SupabaseClient<Database>
}

function createBrowserSupabase(): SupabaseClient<Database> {
  return createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}

/**
 * One browser GoTrue client. A second createClient() on the same storage key
 * auto-refreshes independently; supabase-js warns that concurrent instances
 * produce undefined session behavior. Reuse this singleton across HMR so a
 * re-evaluated module does not start another refresher.
 */
export const supabase: SupabaseClient<Database> =
  (typeof window !== "undefined" ? globalForSupabase.__ttSupabaseBrowser : undefined) ??
  createBrowserSupabase()

if (typeof window !== "undefined") {
  globalForSupabase.__ttSupabaseBrowser = supabase
}
