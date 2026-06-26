import type { SupabaseClient } from "@supabase/supabase-js"
import { removeTradeFromCache } from "./appDataCache"
import { invalidateTradeDetail } from "./tradeDetailCache"
import { invalidateTradeSocial } from "./tradeSocialCache"

/** Deletes a trade and all dependent records via delete_own_trade RPC. */
export async function deleteUserTrade(
  supabase: SupabaseClient,
  tradeId: string,
  options?: { userId?: string | null }
): Promise<void> {
  const { error } = await supabase.rpc("delete_own_trade", {
    p_trade_id: tradeId,
  })

  if (error) {
    throw error
  }

  if (options?.userId) {
    removeTradeFromCache(options.userId, tradeId)
  }
  invalidateTradeDetail(tradeId)
  invalidateTradeSocial(tradeId)
}
