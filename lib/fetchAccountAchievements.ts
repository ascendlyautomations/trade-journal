import type { SupabaseClient } from "@supabase/supabase-js"
import { ACHIEVEMENT_SELECT, type Achievement } from "./achievementTypes"

export async function fetchAchievementsForAccount(
  supabase: SupabaseClient,
  userId: string,
  accountId: string
): Promise<Achievement[]> {
  const { data, error } = await supabase
    .from("achievements")
    .select(ACHIEVEMENT_SELECT)
    .eq("user_id", userId)
    .eq("account_id", accountId)
    .order("achieved_at", { ascending: false })
    .order("created_at", { ascending: false })

  if (error) {
    console.error("[fetchAchievementsForAccount]", error)
    return []
  }

  return (data ?? []) as Achievement[]
}

export async function fetchAchievementsForAccounts(
  supabase: SupabaseClient,
  userId: string,
  accountIds: Array<string | number>
): Promise<Achievement[]> {
  const uniqueIds = [
    ...new Set(accountIds.map((id) => String(id).trim()).filter(Boolean)),
  ]
  if (uniqueIds.length === 0) return []

  const { data, error } = await supabase
    .from("achievements")
    .select(ACHIEVEMENT_SELECT)
    .eq("user_id", userId)
    .in("account_id", uniqueIds)
    .order("achieved_at", { ascending: false })
    .order("created_at", { ascending: false })

  if (error) {
    console.error("[fetchAchievementsForAccounts]", error)
    return []
  }

  return (data ?? []) as Achievement[]
}
