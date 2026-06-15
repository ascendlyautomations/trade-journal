import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"

const DAY_MS = 24 * 60 * 60 * 1000

/** Free plan: max trades created in a rolling 24-hour window (all upload paths). */
export const FREE_PLAN_TRADES_PER_24H = 5

export const FREE_PLAN_TRADE_LIMIT_REACHED = {
  title: "Trade Limit Reached",
  description: `You've reached your limit of ${FREE_PLAN_TRADES_PER_24H} trades in a 24-hour period on the Free plan.`,
} as const

export function freePlanCsvImportLimitExceededMessage(
  csvTradeCount: number,
  remainingUploads: number
) {
  return {
    title: "Import Limit Exceeded",
    description: `Your CSV contains ${csvTradeCount} trades but only ${remainingUploads} uploads remain in your current 24-hour window.`,
  }
}

export function last24hIso(): string {
  return new Date(Date.now() - DAY_MS).toISOString()
}

export async function isUserPro(
  client: SupabaseClient,
  userId: string
): Promise<boolean> {
  const { data } = await client
    .from("profiles")
    .select("is_pro, subscription_status")
    .eq("id", userId)
    .maybeSingle()

  return isProActive(data)
}

export async function countTradesInRolling24h(
  client: SupabaseClient,
  userId: string,
  sinceIso: string = last24hIso()
): Promise<number> {
  const { data, error } = await client
    .from("trades")
    .select("id")
    .eq("user_id", userId)
    .gte("created_at", sinceIso)

  if (error) {
    console.error("trade count failed:", error)
    throw error
  }

  return data?.length ?? 0
}

export type FreePlanTradeUploadAssessment = {
  isPro: boolean
  allowed: boolean
  existingCount: number
  remaining: number
  limit: number
}

/** Validates whether `requestedCount` new trades fit within the free-plan rolling window. */
export async function assessFreePlanTradeUpload(
  client: SupabaseClient,
  userId: string,
  requestedCount: number
): Promise<FreePlanTradeUploadAssessment> {
  const isPro = await isUserPro(client, userId)
  if (isPro) {
    return {
      isPro: true,
      allowed: true,
      existingCount: 0,
      remaining: Number.POSITIVE_INFINITY,
      limit: FREE_PLAN_TRADES_PER_24H,
    }
  }

  const existingCount = await countTradesInRolling24h(client, userId)
  const remaining = Math.max(0, FREE_PLAN_TRADES_PER_24H - existingCount)
  const allowed = requestedCount <= remaining

  return {
    isPro: false,
    allowed,
    existingCount,
    remaining,
    limit: FREE_PLAN_TRADES_PER_24H,
  }
}

export async function hasReachedRowLimit(
  client: SupabaseClient,
  args: {
    table: string
    userColumn: string
    userId: string
    limit: number
    sinceIso?: string
    extraEquals?: Record<string, string | number | boolean>
  }
): Promise<boolean> {
  const sinceIso = args.sinceIso ?? last24hIso()
  let query = client
    .from(args.table)
    .select("id")
    .eq(args.userColumn, args.userId)
    .gte("created_at", sinceIso)

  for (const [key, value] of Object.entries(args.extraEquals ?? {})) {
    query = query.eq(key, value)
  }

  const { data, error } = await query
  if (error) {
    console.error(`limit check failed (${args.table}):`, error)
    return false
  }
  return (data?.length ?? 0) >= args.limit
}

export async function reachedMessagesCommentsLimit(
  client: SupabaseClient,
  userId: string,
  limit = 10
): Promise<boolean> {
  const sinceIso = last24hIso()
  const [dmBySender, globalByUser, postComments, tradeComments, roomMessages] =
    await Promise.all([
      client
        .from("messages")
        .select("id")
        .eq("sender_id", userId)
        .gte("created_at", sinceIso),
      client
        .from("messages")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sinceIso),
      client
        .from("comments")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sinceIso),
      client
        .from("trade_comments")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sinceIso),
      client
        .from("room_messages")
        .select("id")
        .eq("user_id", userId)
        .gte("created_at", sinceIso),
    ])

  const total =
    (dmBySender.data?.length ?? 0) +
    (globalByUser.data?.length ?? 0) +
    (postComments.data?.length ?? 0) +
    (tradeComments.data?.length ?? 0) +
    (roomMessages.data?.length ?? 0)

  return total >= limit
}
