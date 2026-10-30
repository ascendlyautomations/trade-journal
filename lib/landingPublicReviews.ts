import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import type { PublicUserReview } from "./userReviewDisplay.ts"
import { getSupabaseServiceRole } from "./supabaseServiceRole.ts"
import { serviceRoleTableRead } from "./supabaseServiceTableRead.ts"

export async function loadPublicUserReviews(options?: {
  client?: SupabaseClient<Database>
  timeoutMs?: number
}): Promise<PublicUserReview[]> {
  const db = options?.client ?? getSupabaseServiceRole()
  try {
    const data = await serviceRoleTableRead(
      db,
      "landing_public_reviews",
      async (signal) => {
        const result = await db
          .rpc("list_public_user_reviews")
          .abortSignal(signal)
        return {
          data: (result.data as PublicUserReview[] | null) ?? null,
          error: result.error,
        }
      },
      { timeoutMs: options?.timeoutMs }
    )
    return data ?? []
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    console.error("[landing] public reviews fetch failed", message)
    return []
  }
}
