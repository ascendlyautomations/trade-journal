import type { SupabaseClient } from "@supabase/supabase-js"

export function isTradeOwnedByUser(
  trade: { user_id?: string | null } | null | undefined,
  userId: string
): boolean {
  if (!trade?.user_id || !userId) return false
  return String(trade.user_id) === String(userId)
}

/** Verify the sender owns the trade before sharing to conversations. */
export async function assertSenderOwnsTrade(
  client: SupabaseClient,
  tradeId: string,
  senderId: string
): Promise<{ ok: true } | { ok: false; error: Error }> {
  const { data, error } = await client
    .from("trades")
    .select("id, user_id")
    .eq("id", tradeId)
    .maybeSingle()

  if (error) {
    return { ok: false, error: new Error(error.message) }
  }

  if (!isTradeOwnedByUser(data, senderId)) {
    return {
      ok: false,
      error: new Error("You can only share trades you own."),
    }
  }

  return { ok: true }
}
