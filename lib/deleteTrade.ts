import type { SupabaseClient } from "@supabase/supabase-js"
import { assertAccountAllowsTradeWrites } from "./freePlanAccountSlots"
import { isProActive } from "./subscription"
import { removeTradeFromCache } from "./appDataCache"
import { invalidateTradeDetail } from "./tradeDetailCache"
import { invalidateTradeSocial } from "./tradeSocialCache"

/** Deletes a trade and all dependent records via delete_own_trade RPC. */
export async function deleteUserTrade(
  supabase: SupabaseClient,
  tradeId: string,
  options?: {
    userId?: string | null
    profile?: Parameters<typeof isProActive>[0] | null
    knownTraxProActive?: boolean | null
  }
): Promise<void> {
  const userId = options?.userId
  if (userId) {
    const { data: tradeRow } = await supabase
      .from("trades")
      .select("account_id")
      .eq("id", tradeId)
      .eq("user_id", userId)
      .maybeSingle()

    const gate = await assertAccountAllowsTradeWrites(
      supabase,
      userId,
      tradeRow?.account_id != null ? String(tradeRow.account_id) : null,
      options?.profile ?? null,
      options?.knownTraxProActive
    )
    if (!gate.ok) {
      throw new Error(gate.message)
    }
  }

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
