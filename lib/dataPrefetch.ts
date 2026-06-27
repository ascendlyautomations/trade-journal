import type { SupabaseClient } from "@supabase/supabase-js"
import { ensureAccountsLoaded, ensureTradesLoaded } from "./appDataCache"

let warmedUserId: string | null = null

/** Prefetch core trades/accounts caches after auth — speeds first navigation to dashboard/trades. */
export function warmAppDataCaches(
  supabase: SupabaseClient,
  userId: string
) {
  const id = userId.trim()
  if (!id || warmedUserId === id) return
  warmedUserId = id
  void Promise.all([
    ensureTradesLoaded(supabase, id),
    ensureAccountsLoaded(supabase, id),
  ])
}

export function resetDataPrefetchSession() {
  warmedUserId = null
}
