import type { SupabaseClient } from "@supabase/supabase-js"

/** Deletes a trade and all dependent records via delete_own_trade RPC. */
export async function deleteUserTrade(
  supabase: SupabaseClient,
  tradeId: string
): Promise<void> {
  const { error } = await supabase.rpc("delete_own_trade", {
    p_trade_id: tradeId,
  })

  if (error) {
    throw error
  }
}
