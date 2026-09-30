import type { SupabaseClient } from "@supabase/supabase-js"
import { asJsonObject } from "@/lib/supabaseProjectedQuery"

export type OwnerTradeRowsResult = {
  rows: Record<string, unknown>[]
  error: Error | null
}

/** Full owner trade row via `rpc_v1_trade_owner_read` (null if not owned / missing). */
export async function rpcTradeOwnerRead(
  supabase: SupabaseClient,
  tradeId: string
): Promise<Record<string, unknown> | null> {
  const id = tradeId.trim()
  if (!id) return null

  const { data, error } = await supabase.rpc("rpc_v1_trade_owner_read", {
    p_trade_id: id,
  })

  if (error || data == null) return null
  return asJsonObject(data) ?? null
}

/** Owner trade rows via `rpc_v1_trades_owner_rows`. */
export async function rpcTradesOwnerRows(
  supabase: SupabaseClient,
  options?: { tradeIds?: readonly string[]; limit?: number }
): Promise<OwnerTradeRowsResult> {
  const tradeIds = options?.tradeIds?.map((id) => String(id).trim()).filter(Boolean)
  const { data, error } = await supabase.rpc("rpc_v1_trades_owner_rows", {
    p_trade_ids: tradeIds?.length ? tradeIds : null,
    p_limit: options?.limit ?? null,
  })

  if (error) {
    return { rows: [], error: new Error(error.message) }
  }
  if (!Array.isArray(data)) {
    return { rows: [], error: null }
  }
  const rows = data
    .map((row) => asJsonObject(row))
    .filter((row): row is Record<string, unknown> => row != null)
  return { rows, error: null }
}
