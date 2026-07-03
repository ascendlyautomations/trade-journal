import { createClient, type SupabaseClient } from "@supabase/supabase-js"

let serviceClient: SupabaseClient | null = null

/** Service-role Supabase client for server-side reads (never expose to the browser). */
export function getSupabaseServiceRole(): SupabaseClient {
  if (!serviceClient) {
    serviceClient = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    )
  }
  return serviceClient
}
