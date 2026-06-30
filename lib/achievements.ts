import { supabase } from "./supabaseClient"
import { formatPnlCurrency } from "./formatMoney"

export * from "./achievementTypes.ts"

import type { Achievement, PayoutAchievementRow } from "./achievementTypes.ts"
import {
  ACHIEVEMENT_SELECT,
  PUBLIC_ACHIEVEMENT_SELECT,
  buildPayoutTotalsByUserId,
} from "./achievementTypes.ts"

export function formatAchievementValue(a: Achievement): string | null {
  if (a.value_text && a.value_text.trim() !== "") return a.value_text
  if (a.value_numeric == null || !Number.isFinite(Number(a.value_numeric))) {
    return null
  }
  const numeric = Number(a.value_numeric)
  if (a.currency && a.currency.trim() !== "") return formatPnlCurrency(numeric)
  return numeric.toLocaleString()
}

/** Public payout totals for explore / discovery (RLS: is_public only for others). */
export async function fetchPublicPayoutTotalsByUserId(
  userIds: string[]
): Promise<Record<string, number>> {
  const uniqueIds = [...new Set(userIds.map((id) => String(id).trim()).filter(Boolean))]
  if (uniqueIds.length === 0) return {}

  const { data, error } = await supabase
    .from("achievements")
    .select("user_id, achievement_type, value_numeric")
    .in("user_id", uniqueIds)
    .eq("is_public", true)

  if (error) {
    console.error("[achievements] fetchPublicPayoutTotalsByUserId:", error)
    return {}
  }

  return buildPayoutTotalsByUserId((data || []) as PayoutAchievementRow[])
}

export async function fetchOwnAchievements(userId: string) {
  return supabase
    .from("achievements")
    .select(ACHIEVEMENT_SELECT)
    .eq("user_id", userId)
    .order("is_featured", { ascending: false })
    .order("achieved_at", { ascending: false, nullsFirst: false })
    .order("sort_order", { ascending: true, nullsFirst: false })
}

export async function fetchVisibleProfileAchievements(profileUserId: string) {
  return supabase
    .from("achievements")
    .select(PUBLIC_ACHIEVEMENT_SELECT)
    .eq("user_id", profileUserId)
    .eq("is_public", true)
    .order("is_featured", { ascending: false })
    .order("achieved_at", { ascending: false, nullsFirst: false })
    .order("sort_order", { ascending: true, nullsFirst: false })
}
