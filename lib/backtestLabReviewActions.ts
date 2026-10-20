import type { SupabaseClient } from "@supabase/supabase-js"

export async function updateBacktestTradeReviewed(
  client: SupabaseClient,
  tradeId: string,
  userId: string,
  reviewed: boolean
): Promise<{ ok: true } | { ok: false; message: string }> {
  const { error } = await client
    .from("trades")
    .update({ reviewed })
    .eq("id", tradeId)
    .eq("user_id", userId)

  if (error) {
    return { ok: false, message: error.message }
  }
  return { ok: true }
}
