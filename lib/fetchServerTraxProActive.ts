import { supabase } from "./supabaseClient"
import { loadBillingEntitlement } from "./billingEntitlementClient"

/** Returns the shared server snapshot, or null when the request cannot be trusted. */
export async function fetchServerTraxProActive(): Promise<boolean | null> {
  try {
    const {
      data: { session },
    } = await supabase.auth.getSession()
    const userId = session?.user?.id
    if (!userId) return null
    const state = await loadBillingEntitlement(userId)
    if (state.status !== "ready" || !state.snapshot) return null
    return state.snapshot.traxProActive
  } catch {
    return null
  }
}
