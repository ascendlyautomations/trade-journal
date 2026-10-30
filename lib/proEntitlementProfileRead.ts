import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import { serviceRoleTableRead } from "./supabaseServiceTableRead.ts"
import {
  TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS,
  type TraxProEntitlementProfile,
} from "./traxProEntitlement.ts"

/** Timed-out or failed reads return null so callers cannot grant Pro. */
export async function readProEntitlementProfile(
  client: SupabaseClient<Database>,
  userId: string,
  options?: { timeoutMs?: number }
): Promise<TraxProEntitlementProfile | null> {
  try {
    const profile = await serviceRoleTableRead(
      client,
      "pro_entitlement_profile",
      async (signal) => {
        const result = await client
          .from("profiles")
          .select(TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS)
          .eq("id", userId)
          .abortSignal(signal)
          .single<TraxProEntitlementProfile>()
        return { data: result.data, error: result.error }
      },
      { timeoutMs: options?.timeoutMs }
    )
    return profile ?? null
  } catch {
    return null
  }
}
