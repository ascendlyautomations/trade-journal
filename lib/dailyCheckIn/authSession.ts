import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"

/**
 * Wait until the browser client has a JWT before owner-scoped check-in reads.
 * Without this, PostgREST can return an empty set under RLS and poison session cache.
 */
export async function waitForDailyCheckInAuthSession(
  client: SupabaseClient<Database>,
  attempts = 6
): Promise<boolean> {
  for (let i = 0; i < attempts; i += 1) {
    const { data } = await client.auth.getSession()
    if (data.session?.access_token && data.session.user?.id) {
      return true
    }
    if (i + 1 < attempts) {
      await new Promise((resolve) => setTimeout(resolve, 80 * (i + 1)))
    }
  }
  return false
}
