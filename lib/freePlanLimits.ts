import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"

const DAY_MS = 24 * 60 * 60 * 1000

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
