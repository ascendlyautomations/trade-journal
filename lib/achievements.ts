import { supabase } from "./supabaseClient"
import { formatPnlCurrency } from "./formatMoney"

export type AchievementTier = "bronze" | "silver" | "gold" | "platinum" | string

export type AchievementCategory =
  | "payouts"
  | "passed_evals"
  | "milestones"
  | string

export type Achievement = {
  id: string
  user_id: string
  achievement_type: string
  title: string
  description: string | null
  badge_key: string | null
  tier: AchievementTier | null
  category: AchievementCategory | null
  value_numeric: number | null
  value_text: string | null
  currency: string | null
  account_type: string | null
  account_name: string | null
  account_size: string | null
  mode: string | null
  firm: string | null
  achieved_at: string | null
  created_at: string
  updated_at: string
  is_featured: boolean
  is_public: boolean
  sort_order: number | null
  metadata: Record<string, unknown> | null
}

export const ACHIEVEMENT_SELECT = `
  id,
  user_id,
  achievement_type,
  title,
  description,
  badge_key,
  tier,
  category,
  value_numeric,
  value_text,
  currency,
  account_type,
  account_name,
  account_size,
  mode,
  firm,
  achieved_at,
  created_at,
  updated_at,
  is_featured,
  is_public,
  sort_order,
  metadata
`

export function normalizeAchievementType(type: string | null): "payout" | "passed_eval" | "milestone" {
  const t = String(type || "").toLowerCase().trim()
  if (t === "payout" || t.includes("payout")) return "payout"
  if (t === "passed_eval" || t.includes("passed") || t.includes("eval")) return "passed_eval"
  return "milestone"
}

export function categoryFromType(type: string | null): "payouts" | "passed_evals" | "milestones" {
  const normalized = normalizeAchievementType(type)
  if (normalized === "payout") return "payouts"
  if (normalized === "passed_eval") return "passed_evals"
  return "milestones"
}

export function badgeKeyFromType(type: string | null): "payout" | "passed_eval" | "milestone" {
  return normalizeAchievementType(type)
}

export function badgeIconForKey(
  badgeKey: string | null,
  achievementType?: string | null
): string {
  const key = String(badgeKey || "").toLowerCase().trim()
  const fallbackType = normalizeAchievementType(achievementType ?? null)
  if (key.includes("payout")) return "💰"
  if (key.includes("eval") || key.includes("pass")) return "✅"
  if (key.includes("milestone")) return "🏆"
  if (fallbackType === "payout") return "💰"
  if (fallbackType === "passed_eval") return "✅"
  if (fallbackType === "milestone") return "🏆"
  return "⭐"
}

export function tierClassName(tier: string | null): string {
  const t = String(tier || "").toLowerCase()
  if (t === "platinum") return "border-cyan-300/40 bg-cyan-500/10"
  if (t === "gold") return "border-amber-300/40 bg-amber-500/10"
  if (t === "silver") return "border-slate-300/40 bg-slate-400/10"
  if (t === "bronze") return "border-orange-300/40 bg-orange-500/10"
  return "border-white/10 bg-white/5"
}

export function formatAchievementDate(value: string | null): string {
  if (!value) return "—"
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return "—"
  return d.toLocaleDateString()
}

export function formatAchievementValue(a: Achievement): string | null {
  if (a.value_text && a.value_text.trim() !== "") return a.value_text
  if (a.value_numeric == null || !Number.isFinite(Number(a.value_numeric))) return null
  const numeric = Number(a.value_numeric)
  if (a.currency && a.currency.trim() !== "") return formatPnlCurrency(numeric)
  return numeric.toLocaleString()
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
    .select(ACHIEVEMENT_SELECT)
    .eq("user_id", profileUserId)
    .eq("is_public", true)
    .order("is_featured", { ascending: false })
    .order("achieved_at", { ascending: false, nullsFirst: false })
    .order("sort_order", { ascending: true, nullsFirst: false })
}
