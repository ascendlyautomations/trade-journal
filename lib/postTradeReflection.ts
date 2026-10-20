import type { SupabaseClient } from "@supabase/supabase-js"
import { TRADE_REVIEW_EMOTIONS } from "@/lib/psychology/reports/catalog"
import { rpcTradeOwnerRead } from "@/lib/tradeOwnerRead"
import { upsertTradeInCache } from "@/lib/appDataCache"

export { TRADE_REVIEW_EMOTIONS as POST_TRADE_EXIT_EMOTIONS }

export type PostTradeReflectionInput = {
  exitEmotion: string
  executionRating: number
}

export function hasPostTradeReflection(trade: {
  exit_emotion?: string | null
  execution_rating?: number | null
}): boolean {
  const emotion = trade.exit_emotion?.trim()
  const rating = normalizeExecutionRating(trade.execution_rating)
  return Boolean(emotion) || rating != null
}

export function normalizeExecutionRating(value: unknown): number | null {
  if (value == null || value === "") return null
  const n = typeof value === "number" ? value : Number(value)
  if (!Number.isFinite(n)) return null
  const rounded = Math.round(n)
  if (rounded < 1 || rounded > 5) return null
  return rounded
}

export function postTradeReflectionPayload(input: PostTradeReflectionInput): {
  exit_emotion: string | null
  execution_rating: number | null
} {
  const exit_emotion = input.exitEmotion.trim() || null
  const execution_rating =
    input.executionRating > 0 ? normalizeExecutionRating(input.executionRating) : null
  return { exit_emotion, execution_rating }
}

/** Persist owner post-trade reflection (`trades.exit_emotion`, `trades.execution_rating`). */
export async function savePostTradeReflection(
  supabase: SupabaseClient,
  tradeId: string,
  userId: string,
  input: PostTradeReflectionInput
): Promise<Record<string, unknown> | null> {
  const payload = postTradeReflectionPayload(input)

  const { error } = await supabase
    .from("trades")
    .update(payload)
    .eq("id", tradeId)

  if (error) throw error

  const row = await rpcTradeOwnerRead(supabase, tradeId)
  if (row) {
    upsertTradeInCache(userId, row)
  }
  return row
}
