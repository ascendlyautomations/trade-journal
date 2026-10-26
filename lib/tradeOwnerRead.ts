import type { SupabaseClient } from "@supabase/supabase-js"
import { asJsonObject } from "@/lib/supabaseProjectedQuery"
import { reportCriticalOperationFailure } from "@/lib/criticalOperationTelemetry"

export type OwnerTradeRowsResult = {
  rows: Record<string, unknown>[]
  error: Error | null
}

export type OwnerTradeReadResult =
  | { ok: true; row: Record<string, unknown> }
  | {
      ok: false
      reason: "not_found" | "rpc_error" | "invalid_response"
      message: string
      error?: Error
    }

/** Authoritative owner read — distinguishes missing trade from RPC/transport failure. */
export async function rpcTradeOwnerReadResult(
  supabase: SupabaseClient,
  tradeId: string
): Promise<OwnerTradeReadResult> {
  const id = tradeId.trim()
  if (!id) {
    return { ok: false, reason: "not_found", message: "Trade not found." }
  }

  const { data, error } = await supabase.rpc("rpc_v1_trade_owner_read", {
    p_trade_id: id,
  })

  if (error) {
    reportCriticalOperationFailure({
      operation: "trade_owner_read",
      error,
      context: { trade_id: id, code: error.code ?? null },
    })
    return {
      ok: false,
      reason: "rpc_error",
      message: error.message || "Could not load trade.",
      error: new Error(error.message),
    }
  }
  if (data == null) {
    return { ok: false, reason: "not_found", message: "Trade not found." }
  }
  const row = asJsonObject(data)
  if (!row) {
    return {
      ok: false,
      reason: "invalid_response",
      message: "Could not load trade.",
      error: new Error("Invalid rpc_v1_trade_owner_read response"),
    }
  }
  return { ok: true, row }
}

/** Full owner trade row via `rpc_v1_trade_owner_read` (null if not owned / missing / error). */
export async function rpcTradeOwnerRead(
  supabase: SupabaseClient,
  tradeId: string
): Promise<Record<string, unknown> | null> {
  const result = await rpcTradeOwnerReadResult(supabase, tradeId)
  return result.ok ? result.row : null
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
    reportCriticalOperationFailure({
      operation: "trades_owner_rows",
      error,
      context: {
        trade_ids: tradeIds?.length ?? 0,
        limit: options?.limit ?? null,
        code: error.code ?? null,
      },
    })
    return { rows: [], error: new Error(error.message) }
  }
  if (!Array.isArray(data)) {
    return {
      rows: [],
      error: new Error("Invalid rpc_v1_trades_owner_rows response"),
    }
  }
  const rows = data
    .map((row) => asJsonObject(row))
    .filter((row): row is Record<string, unknown> => row != null)
  return { rows, error: null }
}
