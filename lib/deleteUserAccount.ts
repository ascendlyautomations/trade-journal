import type { SupabaseClient } from "@supabase/supabase-js"
import Stripe from "stripe"
import {
  deleteUserAdmin,
  type DeleteUserAdminResult,
} from "@/lib/deleteUserAdmin"

export type DeleteUserAccountInput = {
  userId: string
  stripe?: Stripe | null
}

/** Self-service permanent account deletion (settings → delete account). */
export async function deleteUserAccount(
  supabase: SupabaseClient,
  input: DeleteUserAccountInput
): Promise<DeleteUserAdminResult> {
  return deleteUserAdmin(supabase, {
    adminUserId: input.userId,
    targetUserId: input.userId,
    stripe: input.stripe ?? null,
    selfService: true,
  })
}
